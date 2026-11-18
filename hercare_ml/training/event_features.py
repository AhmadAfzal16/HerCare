"""Prospective source-event export -> leakage-safe features and real outcomes."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from uuid import UUID

import pandas as pd
from training.longitudinal_features import build_features, instant, reject_private


def build_event_features(export: dict):
    if export.get('schema_version') != 2 or export.get('data_kind') != 'real_consented_source_events':
        raise ValueError('Require the protected prospective source-event export')
    reject_private(export)
    source = {name: export.get(name) for name in ['export_id', 'study_id', 'policy_version', 'from', 'to']}
    try:
        export_identity = UUID(source['export_id'])
    except (ValueError, TypeError, AttributeError):
        export_identity = None
    protected = (export_identity is not None and export_identity.int != 0
                 and isinstance(source['study_id'], str) and bool(source['study_id'].strip())
                 and source['policy_version'] == 'research-aggregate-v1')
    participant_map = {p['participant_id']: p for p in export['participants'] if p.get('research_consent') is True}
    if len(participant_map) != len(export['participants']):
        raise ValueError('Duplicate or non-consented participant')
    features, targets = [], []
    end = instant(export['to'] + 'T00:00:00Z') + pd.Timedelta(days=1) - pd.Timedelta(microseconds=1)
    begin = instant(export['from'] + 'T00:00:00Z')
    if end < begin or end - begin > pd.Timedelta(days=91):
        raise ValueError('Protected export date range must be at most 90 days apart')
    if any(event.get('participant_id') not in participant_map for event in export['events']):
        raise ValueError('Source event lacks consented participant provenance')
    ignored_event_types = {'text_signal', 'prediction'}
    for participant_id, profile in participant_map.items():
        zone = profile['timezone']
        events = [e for e in export['events'] if e['participant_id'] == participant_id]
        events.sort(key=lambda e: instant(e['available_at']))
        granted = instant(profile['granted_at'])
        if any(instant(e['available_at']) < granted for e in events):
            raise ValueError('Pre-consent observation found')
        if any(not begin <= instant(event['available_at']) <= end for event in events):
            raise ValueError('Source-event availability falls outside its protected export range')
        signatures, screen_values = set(), {}
        for event in events:
            if not isinstance(event.get('source_record_id'), str) or not event['source_record_id']:
                raise ValueError('Require pseudonymous source-record provenance')
            if event['type'] not in {'profile', 'risk_context', 'mood', 'sleep', 'telemetry', 'therapy', 'screening', *ignored_event_types}:
                raise ValueError('Unknown source event type')
            signature = (event['type'], event['source_record_id'], instant(event['available_at']))
            if signature in signatures:
                raise ValueError('Ambiguous duplicate source-event revision')
            signatures.add(signature)
            performed = instant(event['performed_at'])
            if performed > instant(event['available_at']):
                raise ValueError('Source event cannot be available before being performed')
            if not isinstance(event.get('values'), dict):
                raise ValueError('Source-event values must be an object')
            if event['type'] == 'screening':
                values = event['values']
                if values.get('language') not in {'en', 'ur'} or not isinstance(values.get('version'), str) or not values['version']:
                    raise ValueError('Require exact screening version and supported instrument language')
                identity = (values.get('instrument'), values['version'], values['language'], values.get('score'), performed)
                previous = screen_values.setdefault(event['source_record_id'], identity)
                if previous != identity:
                    raise ValueError('Screening revisions changed an immutable completed outcome')
        events = [event for event in events if event['type'] not in ignored_event_types]
        index_day = max(begin, granted).tz_convert(zone).normalize() + pd.Timedelta(days=14)
        if index_day.tz_convert('UTC') < max(begin, granted) + pd.Timedelta(days=14):
            index_day += pd.Timedelta(days=1)
        while index_day.tz_convert('UTC') <= end:
            index = index_day.tz_convert('UTC')
            # Choose actual revisions available at this index; future revisions
            # never replace earlier values. Completed future assessments are labels.
            latest = {}
            for event in events:
                if instant(event['available_at']) <= index:
                    latest[(event['type'], event['source_record_id'])] = event
            daily = {}
            daily_sources = set()
            screenings = {}
            for event in events:
                if event['type'] == 'screening':
                    screenings.setdefault(event['source_record_id'], event)
            profiles = {}
            for event in latest.values():
                kind, values = event['type'], event['values']
                if kind in {'profile', 'risk_context'}:
                    if kind not in profiles or instant(event['available_at']) > instant(profiles[kind]['available_at']):
                        profiles[kind] = event
                elif kind in {'mood', 'sleep', 'telemetry', 'therapy'}:
                    date = event.get('date')
                    if not date:
                        raise ValueError('Daily observations require a local date')
                    if kind != 'therapy':
                        if (kind, date) in daily_sources:
                            raise ValueError('Ambiguous multiple source records for one measurement/day')
                        daily_sources.add((kind, date))
                    row = daily.setdefault(date, {'participant_id': participant_id, 'date': date,
                                                   'available_at': event['available_at']})
                    row['available_at'] = max(row['available_at'], event['available_at'], key=instant)
                    if kind == 'mood':
                        row.update({k: values.get(k) for k in ['mood_rating', 'energy_level', 'sleep_quality', 'social_support']})
                    elif kind == 'sleep':
                        row.update({k: values.get(k) for k in ['sleep_minutes', 'sleep_awakenings']})
                        row['recorded_sleep_quality'] = values.get('sleep_quality')
                        row.update({k: values.get(k) for k in ['bedtime_local_minutes', 'wake_local_minutes']})
                    elif kind == 'telemetry':
                        row.update({k: values.get(k) for k in ['usage_permission', 'notification_permission',
                            'screen_minutes', 'social_minutes', 'late_night_minutes',
                            'notification_analyzed_count', 'notification_negative_count']})
                    elif values.get('completed') is True:
                        row['therapy_minutes'] = row.get('therapy_minutes', 0) + values['duration_seconds'] / 60
            prepared = {'schema_version': 1, 'data_kind': 'real_consented_observations',
                'participants': [profile], 'indexes': [{'participant_id': participant_id, 'index_at': index.isoformat()}],
                'daily_observations': list(daily.values()),
                'assessments': [{'participant_id': participant_id, 'instrument': e['values']['instrument'],
                    'version': e['values']['version'] + ':' + e['values']['language'],
                    'score': e['values']['score'], 'performed_at': e['performed_at'], 'available_at': e['available_at']}
                    for e in screenings.values()]}
            x, y, _ = build_features(prepared)
            source_profile = profiles.get('profile', {}).get('values', {})
            context = profiles.get('risk_context', {}).get('values', {})
            for name in ['age', 'education_level', 'household_type', 'cesarean', 'baby_female']:
                x[name] = source_profile.get(name)
            x['number_of_children'] = context.get('number_of_children')
            affordable = context.get('basic_needs_affordable')
            x['basic_needs_financial_strain'] = None if not isinstance(affordable, bool) else float(not affordable)
            x['mother_in_law_relationship_quality'] = {'poor': 0.0, 'moderate': .5, 'good': 1.0}.get(context.get('mother_in_law_relationship'))
            x['postpartum_months_self_reported'] = source_profile.get('postpartum_months_self_reported')
            features.append(x)
            targets.append(y)
            index_day += pd.Timedelta(days=7)
    if not features:
        raise ValueError('No eligible index after 14 days of prospective gathering; collect actual follow-up first')
    x, y = pd.concat(features, ignore_index=True), pd.concat(targets, ignore_index=True)
    audit = {'data_kind': 'real_consented_source_events', 'rows': len(x), 'participants': len(participant_map),
             'schema_version': 2, 'extractor_version': 'source-event-features-v2',
             'index_cadence_days': 7, 'warmup_days': 14, 'horizon_days': 14, 'tolerance_days': 3, 'split_group': 'participant_id',
             'source_export': source, 'protected_export_provenance': protected,
             'source_export_sha256': hashlib.sha256(json.dumps(export, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest(),
             'pre_index_available_only': True,
             'recognized_nonpredictor_events_excluded': {kind: sum(event['type'] == kind for event in export['events']) for kind in sorted(ignored_event_types)},
             'predictor_columns': [c for c in x if c not in {'participant_id', 'index_at'}
                                   and not c.endswith(('_version', '_at'))],
             'clinical_promotion_allowed': False, 'missing_outcomes_imputed': False,
             'limitations': ['Instrument/version/language outcomes must be selected before training.',
                            'Weekly windows from one person are dependent; group and temporal validation required.',
                            'No clinician diagnoses, raw journals/chat/audio, inferred obstetric diagnoses or clinical treatment-effect labels.']}
    return x, y, audit


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    if args.output_dir.exists():
        raise FileExistsError('Use a new directory')
    x, y, audit = build_event_features(json.loads(args.input.read_text(encoding='utf-8')))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    x.to_csv(args.output_dir / 'features.csv', index=False)
    y.to_csv(args.output_dir / 'outcomes.csv', index=False)
    audit['table_sha256'] = {name: hashlib.sha256((args.output_dir / name).read_bytes()).hexdigest()
                             for name in ['features.csv', 'outcomes.csv']}
    (args.output_dir / 'audit.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')
