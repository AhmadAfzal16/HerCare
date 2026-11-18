"""Strict future-screen cohort/provenance gates, separate from model fitting."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from uuid import UUID

import numpy as np
import pandas as pd

from training.longitudinal_features import MAX_SCORES, RANGES, day, instant

TASKS = {'incident_screen_positive', 'future_worsening'}
STATIC = {'age': (18, 100), 'number_of_children': (0, 30),
          'basic_needs_financial_strain': (0, 1), 'mother_in_law_relationship_quality': (0, 1),
          'cesarean': (0, 1), 'baby_female': (0, 1), 'postpartum_months_self_reported': (0, 12)}
CATEGORICAL = {'education_level', 'household_type'}
DAILY = ('mood_rating', 'energy_level', 'sleep_quality', 'social_support', 'sleep_minutes',
         'sleep_awakenings', 'recorded_sleep_quality', 'screen_minutes', 'social_minutes', 'late_night_minutes', 'therapy_minutes')
DAILY_SUFFIXES = ('mean', 'sd', 'slope_per_day', 'coverage', 'latest_age_days')
CLOCKS = ('bedtime_local_minutes', 'wake_local_minutes')
KNOWN_PREDICTORS = set(STATIC) | CATEGORICAL | {
    f'{field}_{window}d_{suffix}' for field in DAILY for window in (1, 7, 14, 30)
    for suffix in DAILY_SUFFIXES if window != 1 or suffix not in {'sd', 'slope_per_day'}
} | {f'{name}_{window}d' for name in ('negative_notification_ratio', 'notification_pair_coverage')
     for window in (1, 7, 14, 30)} | {
    f'latest_{instrument}_{suffix}' for instrument in MAX_SCORES for suffix in ('score', 'age_days')
} | {f'{clock}_{window}d_{suffix}' for clock in CLOCKS for window in (1, 7, 14, 30)
     for suffix in ('sin_mean', 'cos_mean', 'coverage', 'latest_age_days')}


@dataclass(frozen=True)
class ForecastSpec:
    instrument: str
    version_language: str
    screen_positive_cutoff: int
    task: str = 'incident_screen_positive'
    horizon_days: int = 14
    tolerance_days: int = 3
    max_baseline_age_days: float | None = None
    minimum_change_points: int = 1
    secondary_version_language: str | None = None

    def __post_init__(self):
        if self.instrument not in MAX_SCORES or self.task not in TASKS:
            raise ValueError('Supported instrument and research target must be declared')
        for version in [self.version_language, self.secondary_version_language]:
            if version is not None and (not isinstance(version, str) or ':' not in version
                                        or not version.rsplit(':', 1)[0].strip()
                                        or version.rsplit(':', 1)[1] not in {'en', 'ur'}):
                raise ValueError('Require exact questionnaire version:language (en or ur)')
        if isinstance(self.screen_positive_cutoff, bool) or not isinstance(self.screen_positive_cutoff, int) \
                or not 1 <= self.screen_positive_cutoff <= MAX_SCORES[self.instrument]:
            raise ValueError('Explicit integer research screen-positive cutoff required')
        if self.horizon_days != 14 or self.tolerance_days != 3:
            raise ValueError('Current declared outcome window is day-14 plus/minus-three days')
        age = self.max_baseline_age_days
        if age is None:
            object.__setattr__(self, 'max_baseline_age_days', 7.0 if self.instrument == 'epds' else 14.0)
        elif isinstance(age, bool) or not isinstance(age, (int, float)) or not np.isfinite(age) or not 0 < age <= 14:
            raise ValueError('Fresh baseline age limit must be in (0,14] days')
        if isinstance(self.minimum_change_points, bool) or not isinstance(self.minimum_change_points, int) \
                or not 1 <= self.minimum_change_points <= MAX_SCORES[self.instrument]:
            raise ValueError('Declare an integer exploratory score-change margin')


def resolve_spec(version: str | ForecastSpec) -> ForecastSpec:
    """Retain legacy PHQ9 API; new CLI requires an explicit research cutoff."""
    return version if isinstance(version, ForecastSpec) else ForecastSpec('phq9', version, 10)


def numeric(frame, name, low, high, integer=False):
    values = pd.to_numeric(frame[name], errors='raise')
    observed = values.dropna()
    if not np.isfinite(observed.to_numpy(dtype=float)).all() or not observed.between(low, high).all() \
            or (integer and not observed.mod(1).eq(0).all()):
        raise ValueError(f'Invalid finite observed measurement: {name}')
    frame[name] = values.astype(float)
    return frame[name]


def aware_series(values, name):
    try:
        return pd.to_datetime(values.map(lambda value: instant(value) if pd.notna(value) else pd.NaT), utc=True)
    except (ValueError, TypeError) as error:
        raise ValueError(f'Invalid timezone-aware timestamp in {name}') from error


def validate_predictors(frame, declared):
    if not isinstance(declared, list) or not all(isinstance(name, str) for name in declared) \
            or len(declared) != len(set(declared)) or any(name not in KNOWN_PREDICTORS for name in declared):
        raise ValueError('Unknown or leaking predictor declaration; use the strict source-event whitelist')
    if not set(declared).issubset(frame.columns):
        raise ValueError('Declared source-event predictors are missing')
    for name in declared:
        if name in CATEGORICAL:
            if any(not isinstance(value, str) or len(value) > 80 for value in frame[name].dropna()):
                raise ValueError('Categorical source measurement must be bounded text')
        elif name in STATIC:
            numeric(frame, name, *STATIC[name], integer=name in {'age', 'number_of_children'})
        elif name.startswith('latest_'):
            instrument = name.split('_')[1]
            numeric(frame, name, 0, MAX_SCORES[instrument] if name.endswith('_score') else 10000,
                    integer=name.endswith('_score'))
        elif name.startswith(('negative_notification_ratio_', 'notification_pair_coverage_')) or name.endswith('_coverage'):
            numeric(frame, name, 0, 1)
        else:
            measurement = next((field for field in (*DAILY, *CLOCKS) if name.startswith(field + '_')), None)
            if name.endswith('_latest_age_days'):
                window = int(name[len(measurement) + 1:].split('d_')[0])
                numeric(frame, name, 1, window, integer=True)
            elif measurement in CLOCKS:
                numeric(frame, name, -1, 1)
            else:
                low, high = RANGES[measurement]
                if name.endswith('_slope_per_day'):
                    numeric(frame, name, -(high - low), high - low)
                elif name.endswith('_sd'):
                    numeric(frame, name, 0, high - low)
                else:
                    numeric(frame, name, low, high)


def verify_provenance(directory, audit):
    source = audit.get('source_export', {})
    try:
        export_identity = UUID(source.get('export_id')) if isinstance(source, dict) else None
    except (ValueError, TypeError, AttributeError):
        export_identity = None
    if not isinstance(source, dict) or audit.get('schema_version') != 2 \
            or audit.get('extractor_version') != 'source-event-features-v2' \
            or audit.get('protected_export_provenance') is not True \
            or source.get('policy_version') != 'research-aggregate-v1' \
            or not isinstance(source.get('study_id'), str) or not source['study_id'].strip() \
            or export_identity is None or export_identity.int == 0 \
            or audit.get('pre_index_available_only') is not True \
            or audit.get('missing_outcomes_imputed') is not False \
            or audit.get('clinical_promotion_allowed') is not False \
            or audit.get('split_group') != 'participant_id' \
            or audit.get('horizon_days') != 14 or audit.get('tolerance_days') != 3:
        raise ValueError('Protected real export provenance is required; regenerate using training.event_features')
    source_hash = audit.get('source_export_sha256', '')
    if not isinstance(source_hash, str) or len(source_hash) != 64 or any(character not in '0123456789abcdef' for character in source_hash):
        raise ValueError('Missing protected source-export checksum')
    try:
        start, end = day(source['from']), day(source['to'])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError('Protected export requires its actual bounded collection dates') from error
    if not 0 <= (end - start).days <= 90:
        raise ValueError('Protected export collection range must be at most 90 days apart')
    expected = audit.get('table_sha256', {})
    if not isinstance(expected, dict):
        raise ValueError('Missing extracted table checksums')
    for filename in ['features.csv', 'outcomes.csv']:
        actual = hashlib.sha256((directory / filename).read_bytes()).hexdigest()
        if expected.get(filename) != actual:
            raise ValueError('Research tables changed after provenance extraction')


def prepare(directory: Path, version: str | ForecastSpec):
    """Actual labelled cohort; missing/wrong-cohort outcomes never become zero."""
    spec = resolve_spec(version)
    audit = json.loads((directory / 'audit.json').read_text(encoding='utf-8'))
    if audit.get('data_kind') != 'real_consented_source_events':
        raise ValueError('Cannot train future screening outcomes on retrospective or synthetic data')
    verify_provenance(directory, audit)
    x = pd.read_csv(directory / 'features.csv', keep_default_na=False, na_values=[''])
    y = pd.read_csv(directory / 'outcomes.csv', keep_default_na=False, na_values=[''])
    validate_predictors(x, audit.get('predictor_columns'))
    primary, keys = spec.instrument, ['participant_id', 'index_at']
    required_x = keys + [f'latest_{primary}_{suffix}' for suffix in ('score', 'version', 'age_days', 'at', 'available_at')]
    required_y = keys + [f'future_{primary}_{suffix}' for suffix in ('score', 'version', 'at', 'available_at')]
    if not set(required_x).issubset(x.columns) or not set(required_y).issubset(y.columns):
        raise ValueError('Missing dated exact-version baseline/follow-up source metadata')
    if x[keys].isna().any().any() or y[keys].isna().any().any() \
            or not x.participant_id.map(lambda value: isinstance(value, str) and bool(value.strip())).all():
        raise ValueError('Require nonempty pseudonymous participant and index provenance')
    if x.duplicated(keys).any() or y.duplicated(keys).any():
        raise ValueError('Duplicate participant/index research row')
    joined = x.merge(y[required_y], on=keys, how='outer', validate='one_to_one', indicator=True)
    if not joined['_merge'].eq('both').all():
        raise ValueError('Every feature row requires a corresponding outcome row, including missing outcomes')
    joined = joined.drop(columns='_merge')
    index = aware_series(joined.index_at, 'index_at')
    baseline = numeric(joined, f'latest_{primary}_score', 0, MAX_SCORES[primary], integer=True)
    future = numeric(joined, f'future_{primary}_score', 0, MAX_SCORES[primary], integer=True)
    baseline_at = aware_series(joined[f'latest_{primary}_at'], 'baseline performed_at')
    baseline_available = aware_series(joined[f'latest_{primary}_available_at'], 'baseline available_at')
    future_at = aware_series(joined[f'future_{primary}_at'], 'future performed_at')
    future_available = aware_series(joined[f'future_{primary}_available_at'], 'future available_at')
    collection_begin = instant(audit['source_export']['from'] + 'T00:00:00Z')
    collection_end = instant(audit['source_export']['to'] + 'T00:00:00Z') + pd.Timedelta(days=1)
    if ((index < collection_begin + pd.Timedelta(days=14)) | (index >= collection_end)
            | (baseline_available < collection_begin) | (future_available >= collection_end)).any():
        raise ValueError('Screen/index records fall outside the protected prospective collection window')
    if ((baseline_at > index) | (baseline_available > index) | (baseline_available < baseline_at)).any():
        raise ValueError('Baseline screening cannot include post-index or unavailable measurements')
    if (future_available < future_at).any():
        raise ValueError('Follow-up cannot be available before it was actually performed')
    horizon = (future_at - index).dt.total_seconds() / 86400
    if (future.notna() & ~horizon.between(11, 17)).any():
        raise ValueError('Observed outcome must be within the declared day-14 plus/minus-three-day window')
    ages = (index - baseline_at).dt.total_seconds() / 86400
    if (baseline.notna() & ~np.isclose(joined[f'latest_{primary}_age_days'], ages, equal_nan=False)).any():
        raise ValueError('Baseline freshness metadata disagrees with actual screening timestamp')
    eligible_baseline = baseline.notna() & baseline_available.notna() \
        & joined[f'latest_{primary}_version'].eq(spec.version_language) & ages.between(0, spec.max_baseline_age_days)
    if spec.task == 'incident_screen_positive':
        eligible_baseline &= baseline.lt(spec.screen_positive_cutoff)
        target = future.ge(spec.screen_positive_cutoff).astype(int)
    else:
        eligible_baseline &= baseline.ge(spec.screen_positive_cutoff)
        target = future.sub(baseline).ge(spec.minimum_change_points).astype(int)
    actual_outcome = future.notna() & future_at.notna() & future_available.notna() \
        & joined[f'future_{primary}_version'].eq(spec.version_language)
    valid = eligible_baseline & actual_outcome
    exclusions = {'total_rows': int(len(joined)), 'missing_followup': int(future.isna().sum()),
                  'ineligible_missing_stale_wrong_version_or_baseline_state': int((~eligible_baseline).sum()),
                  'wrong_version_or_unavailable_followup': int((future.notna() & ~actual_outcome).sum()),
                  'excluded_total': int((~valid).sum())}
    joined, target = joined.loc[valid].copy().reset_index(drop=True), target.loc[valid].reset_index(drop=True)
    if joined.participant_id.nunique() < 30 or len(joined) < 100:
        raise ValueError('Research pilot minimum: 30 participants and 100 actual eligible follow-up rows; not a clinical power calculation')
    if target.nunique() != 2:
        raise ValueError('Both actual future-screen outcome classes are required')
    chosen = chosen_columns(joined, audit['predictor_columns'], spec)
    joined.attrs['audit'], joined.attrs['exclusions'] = audit, exclusions
    return joined, target, chosen, exclusions['excluded_total']


def chosen_columns(frame, declared, spec):
    chosen = [name for name in declared if name in STATIC or name in CATEGORICAL
              or any(name == f'{field}_14d_{suffix}' for field in DAILY for suffix in DAILY_SUFFIXES)
              or any(name == f'{field}_14d_{suffix}' for field in CLOCKS for suffix in ('sin_mean', 'cos_mean', 'coverage', 'latest_age_days'))
              or name in {'negative_notification_ratio_14d', 'notification_pair_coverage_14d'}
              or name in {f'latest_{spec.instrument}_score', f'latest_{spec.instrument}_age_days'}]
    secondary = 'epds' if spec.instrument == 'phq9' else 'phq9'
    if spec.secondary_version_language:
        required = [f'latest_{secondary}_{suffix}' for suffix in ('version', 'at', 'available_at', 'score', 'age_days')]
        if not set(required).issubset(frame.columns):
            raise ValueError('Secondary screening requires its own version/time metadata')
        performed = aware_series(frame[f'latest_{secondary}_at'], 'secondary performed_at')
        available = aware_series(frame[f'latest_{secondary}_available_at'], 'secondary available_at')
        index = aware_series(frame.index_at, 'index_at')
        if ((performed > index) | (available > index) | (available < performed)).any():
            raise ValueError('Secondary screening includes post-index measurements')
        ages = (index - performed).dt.total_seconds() / 86400
        if (frame[f'latest_{secondary}_score'].notna() & ~np.isclose(frame[f'latest_{secondary}_age_days'], ages, equal_nan=False)).any():
            raise ValueError('Secondary freshness metadata disagrees with actual timestamp')
        valid = frame[f'latest_{secondary}_version'].eq(spec.secondary_version_language) \
            & available.notna() & ages.between(0, 7 if secondary == 'epds' else 14)
        for suffix in ['score', 'age_days']:
            name = f'latest_{secondary}_{suffix}'
            frame.loc[~valid, name] = np.nan
            if name in declared:
                chosen.append(name)
    if not chosen:
        raise ValueError('No predeclared observed predictors available')
    return sorted(set(chosen))
