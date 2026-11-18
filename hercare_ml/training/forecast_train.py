"""Research-only future-screen classification with full participant-grouped nested CV.

Screen positivity is not diagnosed depression onset. Higher future screening
scores are not validated clinical deterioration. No artifact is auto-promoted.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import UTC, datetime
import json
from pathlib import Path

import joblib
import numpy as np
from sklearn.base import clone
from sklearn.calibration import CalibratedClassifierCV
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.frozen import FrozenEstimator
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.utils.class_weight import compute_sample_weight

from training.curated_train import evaluate
from training.forecast_cohort import CATEGORICAL, ForecastSpec, TASKS, prepare, resolve_spec
from training.longitudinal_features import MAX_SCORES


def build_pipeline(columns, estimator):
    categories = [name for name in columns if name in CATEGORICAL]
    numeric = [name for name in columns if name not in CATEGORICAL]
    preprocessing = ColumnTransformer([
        ('numeric', Pipeline([('impute', SimpleImputer(strategy='median', add_indicator=True, keep_empty_features=True)),
                              ('scale', StandardScaler())]), numeric),
        ('categorical', Pipeline([('impute', SimpleImputer(strategy='constant', fill_value='__missing__')),
                                  ('encode', OneHotEncoder(handle_unknown='ignore', sparse_output=False))]), categories)])
    return Pipeline([('preprocess', preprocessing), ('model', clone(estimator))])


def candidate_grid(seed=42):
    """Small predeclared grid, with no search for artificial 90% performance."""
    result = []
    for weight in ['none', 'balanced']:
        for strength in [0.1, 1.0]:
            result.append(('logistic', f'C={strength};weights={weight}',
                           LogisticRegression(C=strength, solver='liblinear', max_iter=2000, random_state=seed), weight))
        for depth in [3, 5]:
            result.append(('forest', f'depth={depth};weights={weight}',
                           RandomForestClassifier(n_estimators=150, max_depth=depth, min_samples_leaf=8,
                                                  max_features='sqrt', n_jobs=2, random_state=seed), weight))
        for depth in [1, 2]:
            result.append(('boosting', f'depth={depth};weights={weight}',
                           GradientBoostingClassifier(n_estimators=80, learning_rate=.05, max_depth=depth,
                                                      min_samples_leaf=8, random_state=seed), weight))
    return result


def _group_partition(y, groups, fit, validation, label):
    if set(groups.iloc[fit]) & set(groups.iloc[validation]):
        raise ValueError(f'Participant leakage in {label}')
    for name, indexes in [('fit', fit), ('validation', validation)]:
        if y.iloc[indexes].nunique() != 2 or any(groups.iloc[indexes][y.iloc[indexes].eq(value)].nunique() < 2 for value in (0, 1)):
            raise ValueError(f'Insufficient class-specific participant groups in {label}/{name}; more genuine follow-ups required')


def grouped_folds(y, groups, splits, seed, label):
    if isinstance(splits, bool) or not isinstance(splits, int) or splits < 2:
        raise ValueError('At least two participant-grouped folds required')
    if any(groups[y.eq(value)].nunique() < splits for value in (0, 1)):
        raise ValueError(f'Insufficient class-specific participant groups for {label}')
    folds = list(StratifiedGroupKFold(n_splits=splits, shuffle=True, random_state=seed).split(np.zeros(len(y)), y, groups))
    for fit, validation in folds:
        _group_partition(y, groups, fit, validation, label)
    return folds


def _fit(pipeline, x, y, weight):
    weights = compute_sample_weight('balanced', y) if weight == 'balanced' else np.ones(len(y))
    pipeline.fit(x, y, model__sample_weight=weights)
    return pipeline


def _inner_select(x, y, groups, columns, candidates, splits, seed):
    folds = grouped_folds(y, groups, splits, seed, 'inner tuning')
    scores = []
    for family, identifier, estimator, weight in candidates:
        values = []
        for fit, validation in folds:
            candidate = _fit(build_pipeline(columns, estimator), x.iloc[fit], y.iloc[fit], weight)
            values.append(float(roc_auc_score(y.iloc[validation], candidate.predict_proba(x.iloc[validation])[:, 1])))
        scores.append({'family': family, 'parameters': identifier, 'mean_inner_auc': float(np.mean(values)), 'fold_auc': values})
    family_indices = {family: max((i for i, candidate in enumerate(candidates) if candidate[0] == family),
                                 key=lambda i: scores[i]['mean_inner_auc']) for family in {entry[0] for entry in candidates}}
    selected = max(range(len(candidates)), key=lambda i: scores[i]['mean_inner_auc'])
    return selected, family_indices, scores


def _calibrated(x, y, columns, candidate, fit, calibration):
    _, _, estimator, weight = candidate
    pipeline = _fit(build_pipeline(columns, estimator), x.iloc[fit], y.iloc[fit], weight)
    calibrated = CalibratedClassifierCV(FrozenEstimator(pipeline), method='sigmoid')
    calibrated.fit(x.iloc[calibration], y.iloc[calibration])
    return calibrated


def _metrics(y, probabilities):
    metrics = evaluate(y, probabilities, .5)
    (tn, fp), (fn, tp) = metrics['confusion_matrix']
    metrics['positive_predictive_value'] = tp / (tp + fp) if tp + fp else None
    metrics['negative_predictive_value'] = tn / (tn + fn) if tn + fn else None
    bins = []
    for lower in np.linspace(0, .8, 5):
        upper = lower + .2
        members = (probabilities >= lower) & ((probabilities < upper) if upper < 1 else (probabilities <= 1))
        count = int(members.sum())
        bins.append({'lower': float(lower), 'upper': float(upper), 'count': count,
                     'mean_probability': float(probabilities[members].mean()) if count else None,
                     'observed_fraction': float(np.asarray(y)[members].mean()) if count else None})
    metrics['calibration_bins'] = bins
    return metrics


def nested_group_evaluation(frame, target, columns, *, outer_splits=5, inner_splits=3,
                            calibration_splits=4, candidates=None, seed=42):
    """Evaluate every outer fold; calibrate on separate outer-training groups only."""
    x, groups = frame[columns], frame.participant_id
    candidates = candidates if candidates is not None else candidate_grid(seed)
    if not candidates or len({(entry[0], entry[1]) for entry in candidates}) != len(candidates):
        raise ValueError('Candidate grid must be nonempty with unique family/parameter identities')
    outer = grouped_folds(target, groups, outer_splits, seed, 'outer estimation')
    families = sorted({entry[0] for entry in candidates})
    predictions = {name: np.full(len(target), np.nan) for name in [*families, 'inner_selected_policy']}
    folds = []
    for fold, (training, test) in enumerate(outer):
        fit_local, calibration_local = grouped_folds(target.iloc[training].reset_index(drop=True),
            groups.iloc[training].reset_index(drop=True), calibration_splits, seed + 100 + fold, 'training-only calibration')[0]
        fit, calibration = training[fit_local], training[calibration_local]
        selected, family_indices, inner = _inner_select(x.iloc[fit].reset_index(drop=True),
            target.iloc[fit].reset_index(drop=True), groups.iloc[fit].reset_index(drop=True),
            columns, candidates, inner_splits, seed + 200 + fold)
        results = {}
        for family, candidate_index in family_indices.items():
            calibrated = _calibrated(x, target, columns, candidates[candidate_index], fit, calibration)
            probabilities = calibrated.predict_proba(x.iloc[test])[:, 1]
            predictions[family][test] = probabilities
            results[family] = _metrics(target.iloc[test], probabilities)
            if candidate_index == selected:
                predictions['inner_selected_policy'][test] = probabilities
        folds.append({'fold': fold + 1, 'partitions': {
            name: {'rows': len(indexes), 'participants': int(groups.iloc[indexes].nunique()),
                   'class_counts': {str(key): int(value) for key, value in target.iloc[indexes].value_counts().items()}}
            for name, indexes in [('fit', fit), ('calibration', calibration), ('outer_test', test)]},
            'participant_disjoint': True, 'selected_by_inner_only': {'family': candidates[selected][0], 'parameters': candidates[selected][1]},
            'inner_tuning': inner, 'outer_metrics_by_family': results})
    if any(not np.isfinite(values).all() for values in predictions.values()):
        raise ValueError('Incomplete outer out-of-fold estimates')
    report = {'outer_folds': outer_splits, 'inner_folds': inner_splits, 'calibration_partition_folds': calibration_splits,
              'threshold': .5, 'selection_metric': 'inner ROC AUC only', 'folds': folds,
              'out_of_fold_metrics': {name: _metrics(target, values) for name, values in predictions.items()},
              'uncertainty_warning': 'Repeated windows are participant-dependent; row-level confidence intervals are not valid.'}
    return report, predictions


def train(directory: Path, output: Path, version: str | ForecastSpec, *, outer_splits=5, inner_splits=3, calibration_splits=4):
    if output.exists():
        raise FileExistsError('Use a new research experiment directory')
    spec = resolve_spec(version)
    frame, target, columns, excluded = prepare(directory, spec)
    report, predictions = nested_group_evaluation(frame, target, columns, outer_splits=outer_splits,
        inner_splits=inner_splits, calibration_splits=calibration_splits)
    # Repeat selection inside final fit/calibration groups, never using outer results.
    fit, calibration = grouped_folds(target, frame.participant_id, calibration_splits, 142, 'final research calibration')[0]
    candidates = candidate_grid()
    selected, _, final_inner = _inner_select(frame[columns].iloc[fit].reset_index(drop=True),
        target.iloc[fit].reset_index(drop=True), frame.participant_id.iloc[fit].reset_index(drop=True),
        columns, candidates, inner_splits, 242)
    artifact = _calibrated(frame[columns], target, columns, candidates[selected], fit, calibration)
    metadata = {'model_version': 'future-screen-research-v2', 'task': spec.task, 'target_spec': asdict(spec),
                'trained_at': datetime.now(UTC).isoformat(), 'feature_names': columns,
                'screen_positive_cutoff_is': 'Declared research surrogate, not an approved clinical diagnosis/alert threshold',
                'target_meaning': ('Fresh below-cutoff baseline to actual above/equal-cutoff same-version future screen'
                    if spec.task == 'incident_screen_positive' else 'Symptomatic baseline to future score increase >= declared points; negative means NOT worsening, not improvement/remission'),
                'excluded_rows': excluded, 'exclusions': frame.attrs['exclusions'], 'provenance': frame.attrs['audit'],
                'cohort': {'rows': len(frame), 'participants': int(frame.participant_id.nunique()),
                    'observed_predictor_rows': {name: int(frame[name].notna().sum()) for name in columns},
                    'class_counts': {str(key): int(value) for key, value in target.value_counts().items()}},
                'nested_evaluation': report, 'final_selection': {'family': candidates[selected][0], 'parameters': candidates[selected][1],
                'source': 'Final fit-participant inner CV only; outer metrics not used', 'inner_tuning': final_inner},
                'preprocessing': 'Train-fold median imputation + missing indicators; entirely missing fit features use structural zero + indicator, never healthy observations; categorical explicit missing + unseen-safe one-hot; train-fold scaling',
                'balancing': 'None versus inverse-class-frequency weights tuned inside inner fit folds only; no synthetic data or resampling',
                'calibration': 'Sigmoid on separate training-only participant groups at observed prevalence',
                'deployment_eligible': False, 'clinical_validation': False,
                'limitations': ['Screening instruments are not clinical diagnoses; symptom increase is not validated deterioration.',
                    'Export identifiers/checksums support reproducibility and tamper detection, not cryptographic authenticity; operator must verify approved source and consent.',
                    'No proof of depression prevention, remission, treatment effect, or 90% accuracy.',
                    'Group CV does not replace future-time/site/external and clinician-reviewed validation.',
                    'Thirty participants/100 rows is an engineering pilot floor, not a clinical power calculation.',
                    'Dependent weekly windows and missing follow-up can bias estimates; participant-level uncertainty and attrition analysis required.']}
    output.mkdir(parents=True, exist_ok=False)
    joblib.dump({'research_pipeline': artifact, 'metadata': metadata}, output / 'future_screen_research.joblib')
    (output / 'report.json').write_text(json.dumps(metadata, indent=2, allow_nan=False), encoding='utf-8')
    estimates = frame[['participant_id', 'index_at']].copy()
    estimates['observed_research_target'] = target
    for family, probabilities in predictions.items():
        estimates[f'{family}_outer_probability'] = probabilities
    estimates.to_csv(output / 'outer_predictions.csv', index=False)
    return metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--instrument', choices=sorted(MAX_SCORES), required=True)
    parser.add_argument('--instrument-version-language', required=True)
    parser.add_argument('--screen-positive-cutoff', type=int, required=True)
    parser.add_argument('--task', choices=sorted(TASKS), default='incident_screen_positive')
    parser.add_argument('--secondary-version-language')
    parser.add_argument('--maximum-baseline-age-days', type=float)
    parser.add_argument('--minimum-change-points', type=int, default=1)
    parser.add_argument('--outer-folds', type=int, default=5)
    parser.add_argument('--inner-folds', type=int, default=3)
    args = parser.parse_args()
    spec = ForecastSpec(args.instrument, args.instrument_version_language, args.screen_positive_cutoff,
        args.task, max_baseline_age_days=args.maximum_baseline_age_days,
        minimum_change_points=args.minimum_change_points, secondary_version_language=args.secondary_version_language)
    train(args.input_dir, args.output_dir, spec, outer_splits=args.outer_folds, inner_splits=args.inner_folds)
