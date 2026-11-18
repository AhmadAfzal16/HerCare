"""Train and evaluate M4 only on generated observations. No application data is read."""
from __future__ import annotations

import argparse
from datetime import date, timedelta
import json
import math
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.metrics import brier_score_loss, confusion_matrix, mean_absolute_error, roc_auc_score, roc_curve
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


DATA_KIND = 'synthetic_simulation_only'
GENERATOR_VERSION = 'm4-simulation-v1'
WINDOWS_PER_MOTHER = 3
HORIZON_DAYS = 14
SCREEN_CUTOFF = 13
CHANGE_POINTS = 4
BAND_CUTOFFS = [9, 13, 19]
BAND_LABELS = ['low', 'moderate', 'high', 'severe']
DIRECTION_LABELS = ['improving', 'stable_under_rule', 'worsening']
KEYS = ['participant_id', 'index_day', 'data_kind']
EPDS_ONLY = ['epds_latest', 'epds_previous', 'epds_previous_age_days']


def _bounded(value, high=30):
    return int(np.clip(np.rint(value), 0, high))


def _rating(value):
    return int(np.clip(np.rint(value), 1, 5))


def _profile(rng, participant_id):
    parity = int(rng.integers(0, 5))
    return {
        'participant_id': participant_id,
        'age': int(rng.integers(18, 46)),
        'postpartum_month_at_enrollment': float(rng.uniform(0, 9)),
        'education': rng.choice(['none', 'primary', 'secondary', 'higher']),
        'household_type': rng.choice(['nuclear', 'joint']),
        'monthly_income_band': int(rng.integers(1, 6)),
        'main_supporter': rng.choice(['partner', 'mother_in_law', 'siblings', 'none']),
        'previous_deliveries': parity,
        'living_children': parity + 1,
        'basic_needs_affordable': int(rng.random() > .20),
        'mother_in_law_relationship': rng.choice(['poor', 'moderate', 'good']),
        'delivery_method': rng.choice(['vaginal', 'cesarean']),
        'baby_sex': rng.choice(['female', 'male']),
        **{name: int(rng.random() < prevalence) for name, prevalence in {
            'preeclampsia': .08, 'postpartum_hemorrhage': .06,
            'preterm_birth': .10, 'gestational_diabetes': .10,
        }.items()},
    }


def _signals(rng, baseline, trend, financial_pressure, relationship_pressure):
    # Measurements overlap in real applications. Here several noisy measurements
    # share a latent state so the regression must handle correlated predictors.
    return {
        'mood': _rating(4.1 - .13 * baseline - .22 * trend + rng.normal(0, .7)),
        'energy': _rating(4.2 - .12 * baseline - .18 * trend + rng.normal(0, .7)),
        'mood_sleep_quality': _rating(4.5 - .12 * baseline - .16 * trend + rng.normal(0, .8)),
        'daily_support': _rating(4.3 - .26 * relationship_pressure + rng.normal(0, .6)),
        'sleep_duration_minutes': _bounded(465 - 5 * baseline - 12 * trend + rng.normal(0, 38), 840),
        'sleep_awakenings': _bounded(.8 + .13 * baseline + .31 * trend + rng.normal(0, .7), 20),
        'sleep_awake_minutes': _bounded(15 + 3 * baseline + 5 * trend + rng.normal(0, 18), 300),
        'sleep_diary_quality': _rating(4.4 - .13 * baseline - .17 * trend + rng.normal(0, .6)),
        'bedtime_variability_minutes': _bounded(26 + 2 * baseline + 3 * trend + rng.normal(0, 12), 240),
        'wake_variability_minutes': _bounded(33 + 2 * baseline + 3 * trend + rng.normal(0, 12), 240),
        'financial_strain': _bounded(.8 + .38 * financial_pressure + rng.normal(0, .45), 3),
        'relationship_strain': _bounded(1 + .43 * relationship_pressure + rng.normal(0, .5), 3),
        'support_gap': _bounded(1 + .28 * relationship_pressure + .15 * trend + rng.normal(0, .65), 3),
        'recovery_difficulty': _bounded(.8 + .12 * baseline + .23 * trend + rng.normal(0, .6), 3),
    }


def _optional_signals(rng, state, trend):
    # Optional text consists of counts of distinct days. Same-day journal and
    # chatbot cues are represented once. No synthetic phrases or raw data needed.
    if rng.random() < .68:
        days = int(rng.integers(1, 15))
        text_days = int(rng.binomial(days, np.clip(.05 + .019 * state + .035 * trend, .02, .70)))
    else:
        days = text_days = None
    result = {'text_analyzed_days': days, 'text_distress_days': text_days}
    if rng.random() < .62:
        result.update(
            phone_screen_minutes=_bounded(185 + 7 * trend + rng.normal(0, 65), 1440),
            phone_social_minutes=_bounded(75 + 4 * trend + rng.normal(0, 35), 1440),
            phone_late_minutes=_bounded(50 + 9 * trend + rng.normal(0, 27), 480),
            phone_app_switches=_bounded(80 + 5 * trend + rng.normal(0, 22), 700),
            phone_usage_days=int(rng.integers(4, 15)),
        )
    if rng.random() < .44:
        analyzed = int(rng.integers(8, 145))
        negative = rng.binomial(analyzed, np.clip(.10 + .023 * trend, .01, .50))
        result.update(notification_analyzed=analyzed,
                      notification_negative_ratio=negative / analyzed,
                      notification_distress_ratio=rng.binomial(negative, .28) / analyzed,
                      notification_abuse_ratio=rng.binomial(negative, .08) / analyzed)
    return result


def generate(seed, participants, *, shifted=False):
    """Generate prior observations and later labels with artificial assumptions."""
    rng = np.random.default_rng(seed)
    predictors, outcomes = [], []
    for i in range(participants):
        prefix = 'shift' if shifted else 'reference'
        profile = _profile(rng, f'sim-{prefix}-{i:05d}')
        enrollment = date(2025, 1, 1) + timedelta(days=int(rng.integers(0, 45)))
        financial_pressure = rng.normal(0, 1) + .8 * (1 - profile['basic_needs_affordable'])
        relationship_pressure = rng.normal(0, 1)
        state = rng.normal(8, 5)
        previous_trend = rng.normal(0, 2)
        # Mask each optional profile answer once per person. A real zero is
        # distinct from a skipped answer, even for a complication checkbox.
        observed_profile = {key: value if key in {'participant_id', 'age', 'postpartum_month_at_enrollment'}
                            or rng.random() > .13 else None for key, value in profile.items()}
        for window in range(WINDOWS_PER_MOTHER):
            index_day = enrollment + timedelta(days=window * 28)
            trend = .43 * previous_trend + rng.normal(0, 1.85)
            financial_pressure += rng.normal(0, .55)
            relationship_pressure += rng.normal(0, .55)
            epds = _bounded(state + rng.normal(0, 1.5))
            previous_age_days = int(rng.integers(5, 10))
            signals = _signals(rng, state, trend, financial_pressure, relationship_pressure)
            signals = {name: value if rng.random() > .17 else None for name, value in signals.items()}
            predictors.append({
                **observed_profile,
                'data_kind': DATA_KIND,
                'index_day': index_day.isoformat(),
                'epds_latest': epds,
                'epds_previous': _bounded(state - previous_trend + rng.normal(0, 1.7)),
                'epds_previous_age_days': previous_age_days,
                'phq9_latest': _bounded(.88 * state + rng.normal(0, 2.2), 27) if rng.random() < .74 else None,
                'phq9_previous': _bounded(.88 * (state - previous_trend) + rng.normal(0, 2.2), 27)
                if rng.random() < .64 else None,
                'postpartum_month_at_index': round(profile['postpartum_month_at_enrollment'] + window * 28 / 30.4, 2),
                'mood_observed_days': int(rng.integers(3, 15)),
                'sleep_observed_days': int(rng.integers(2, 15)),
                'context_checkin_age_days': int(rng.integers(0, 8)),
                **signals,
                **_optional_signals(rng, state, trend),
            })
            # The arbitrary coefficients create a known signal with label noise.
            # The stress test weakens the links and raises outcome noise.
            context = .5 * financial_pressure + .55 * relationship_pressure
            signal_strength = .42 if shifted else 1.
            next_state = 8 + .80 * (state - 8) + signal_strength * (.95 * trend + context)
            future = _bounded(next_state + rng.normal(0, 4.4 if shifted else 3.3))
            observed_lag = int(rng.integers(11, 18))
            outcomes.append({
                'participant_id': profile['participant_id'],
                'data_kind': DATA_KIND,
                'index_day': index_day.isoformat(),
                'followup_day': (index_day + timedelta(days=observed_lag)).isoformat(),
                'future_epds': future,
            })
            state = next_state + rng.normal(0, 1.1)
            previous_trend = trend
    return pd.DataFrame(predictors), pd.DataFrame(outcomes)


def split_participants(frame, seed):
    groups = np.array(sorted(frame['participant_id'].unique()))
    np.random.default_rng(seed).shuffle(groups)
    fit, calibration, test = np.split(groups, [int(len(groups) * .60), int(len(groups) * .80)])
    return {name: frame[frame['participant_id'].isin(ids)].reset_index(drop=True)
            for name, ids in [('fit', fit), ('calibration', calibration), ('test', test)]}


def build_model(frame, columns, estimator):
    categories = [name for name in columns if frame[name].dtype == 'object']
    numbers = [name for name in columns if name not in categories]
    preprocess = ColumnTransformer([
        ('numbers', make_pipeline(SimpleImputer(strategy='median', add_indicator=True),
                                  StandardScaler()), numbers),
        ('categories', make_pipeline(SimpleImputer(strategy='constant', fill_value='missing',
                                                   missing_values=None),
                                     OneHotEncoder(handle_unknown='ignore', sparse_output=False)), categories),
    ])
    return make_pipeline(preprocess, estimator)


def _direction(latest, values):
    return np.digitize(np.asarray(values) - latest, [-CHANGE_POINTS + 1, CHANGE_POINTS])


def _classification(actual, predicted, labels):
    matrix = confusion_matrix(actual, predicted, labels=range(len(labels)))
    return {
        'labels': labels,
        'counts': matrix.sum(axis=1).tolist(),
        'confusion_matrix': matrix.tolist(),
        'accuracy_percent': round(100 * float(np.trace(matrix)) / len(actual), 2),
        'majority_baseline_accuracy_percent': round(100 * int(matrix.sum(axis=1).max()) / len(actual), 2),
        'recall_percent_by_class': {
            label: round(100 * matrix[i, i] / count, 2) if count else None
            for i, (label, count) in enumerate(zip(labels, matrix.sum(axis=1)))
        },
    }


def _incident_result(actual, prediction, rank_score):
    result = _classification(actual, prediction, ['below_cutoff', 'new_positive'])
    result['auroc'] = round(float(roc_auc_score(actual, rank_score)), 4) if np.unique(actual).size == 2 else None
    tn, fp, fn, tp = np.ravel(result['confusion_matrix'])
    result['warning_precision_percent'] = round(100 * int(tp) / (tp + fp), 2) if tp + fp else None
    result['false_alarm_percent'] = round(100 * int(fp) / (tn + fp), 2) if tn + fp else None
    return result


def _fit_incident_calibration(frame, estimates):
    eligible = frame.epds_latest.to_numpy() < SCREEN_CUTOFF
    actual = frame.future_epds.to_numpy()[eligible] >= SCREEN_CUTOFF
    if np.unique(actual).size < 2:
        return None, None
    score = np.asarray(estimates)[eligible].reshape(-1, 1)
    calibrator = LogisticRegression(solver='liblinear').fit(score, actual)
    probability = calibrator.predict_proba(score)[:, 1]
    false_alarm, sensitivity, thresholds = roc_curve(actual, probability, drop_intermediate=False)
    finite = np.isfinite(thresholds)
    threshold = float(thresholds[finite][np.argmax((sensitivity - false_alarm)[finite])])
    return calibrator, threshold


def _evaluate_incident_calibration(actual, estimate, calibrator, threshold):
    if calibrator is None:
        return {'status': 'insufficient_classes_in_calibration'}
    probability = calibrator.predict_proba(estimate.reshape(-1, 1))[:, 1]
    result = _incident_result(actual, probability >= threshold, probability)
    result.update(status='synthetic_calibration', threshold=round(threshold, 6),
                  brier_score=round(float(brier_score_loss(actual, probability)), 4),
                  mean_probability=round(float(np.mean(probability)), 4),
                  observed_event_rate=round(float(np.mean(actual)), 4))
    return result


def metrics(frame, prediction, radius, calibrator, threshold):
    latest = frame['epds_latest'].to_numpy()
    actual = frame['future_epds'].to_numpy()
    estimate = np.asarray(prediction).clip(0, 30)
    rounded = np.rint(estimate).astype(int)
    incident = latest < SCREEN_CUTOFF
    y = actual[incident] >= SCREEN_CUTOFF
    return {
        'mae_epds_points': round(float(mean_absolute_error(actual, estimate)), 3),
        'interval_calibrated_absolute_error_radius': round(radius, 3),
        'interval_empirical_coverage_percent': round(100 * float(np.mean(np.abs(actual - estimate) <= radius)), 2),
        'incident_positive': _incident_result(y, rounded[incident] >= SCREEN_CUTOFF, estimate[incident]),
        'incident_early_warning': _evaluate_incident_calibration(y, estimate[incident], calibrator, threshold),
        'followup_severity': _classification(np.digitize(actual, BAND_CUTOFFS),
                                               np.digitize(rounded, BAND_CUTOFFS), BAND_LABELS),
        'symptom_direction': _classification(_direction(latest, actual), _direction(latest, rounded), DIRECTION_LABELS),
    }


def _radius(frame, predictions):
    # One calibration error per independent mother. Empirical coverage of the
    # resulting 90% interval is reported on all test windows and again under shift.
    residual = frame[['participant_id']].assign(error=np.abs(frame.future_epds - predictions))
    errors = np.sort(residual.drop_duplicates('participant_id', keep='last').error.to_numpy())
    index = min(len(errors), math.ceil(.90 * (len(errors) + 1))) - 1
    return float(errors[index])


def experiment(output, seed=42, participants=600):
    if not 100 <= participants <= 5000:
        raise ValueError('Use between 100 and 5000 simulated mothers')
    if output.exists():
        raise FileExistsError('Choose a fresh experiment directory')

    x, outcomes = generate(seed, participants)
    x_shift, outcomes_shift = generate(seed + 1, max(100, participants // 3), shifted=True)
    reference = x.merge(outcomes, on=KEYS, validate='one_to_one')
    shifted = x_shift.merge(outcomes_shift, on=KEYS, validate='one_to_one')
    parts = split_participants(reference, seed + 2)
    fit, calibration, test = (parts[name] for name in ['fit', 'calibration', 'test'])
    columns = [column for column in x.columns if column not in KEYS]
    estimators = {
        'epds_only_ridge': (EPDS_ONLY, Ridge(alpha=10.)),
        'all_inputs_ridge': (columns, Ridge(alpha=10.)),
        'all_inputs_boosting': (columns, HistGradientBoostingRegressor(
            max_iter=100, max_leaf_nodes=8, min_samples_leaf=20, l2_regularization=2.,
            random_state=seed, early_stopping=False)),
    }
    models, model_metrics = {}, {}
    for name, (fields, estimator) in estimators.items():
        model = build_model(fit, fields, estimator).fit(fit[fields], fit['future_epds'])
        models[name] = {'estimator': model, 'feature_names': list(fields)}
    models['carry_forward'] = {'estimator': None, 'feature_names': ['epds_latest']}

    for name, entry in models.items():
        model, fields = entry['estimator'], entry['feature_names']
        estimates = [model.predict(frame[fields]).clip(0, 30) if model is not None
                     else frame['epds_latest'].to_numpy() for frame in [calibration, test, shifted]]
        radius = _radius(calibration, estimates[0])
        calibrator, threshold = _fit_incident_calibration(calibration, estimates[0])
        entry['synthetic_interval_radius'] = radius
        entry['synthetic_incident_calibrator'] = calibrator
        entry['synthetic_incident_warning_threshold'] = threshold
        model_metrics[name] = {'reference_holdout': metrics(test, estimates[1], radius, calibrator, threshold),
                               'shifted_holdout': metrics(shifted, estimates[2], radius, calibrator, threshold)}

    report = {
        'data_kind': DATA_KIND,
        'clinical_promotion_allowed': False,
        'generator_version': GENERATOR_VERSION,
        'seed': seed,
        'horizon_days': HORIZON_DAYS,
        'followup_day_range': [11, 17],
        'screen_cutoff': SCREEN_CUTOFF,
        'direction_change_points': CHANGE_POINTS,
        'severity_band_starts': BAND_CUTOFFS,
        'nominal_interval_coverage_percent': 90,
        'incident_warning_threshold_selection': 'Maximum sensitivity minus false alarm rate on calibration mothers',
        'feature_names': columns,
        'partitions': {name: {'participants': int(frame.participant_id.nunique()), 'rows': len(frame)}
                       for name, frame in {**parts, 'shifted_test': shifted}.items()},
        'models': model_metrics,
        'limitations': [
            'All observations and outcomes were generated; metrics only measure behavior in this simulator.',
            'Reference and shifted cohorts share no participants. Shifted outcomes have more noise and weaker predictor links.',
            'Missingness is simulated; outcome availability and patient consent are not represented by this experiment.',
            'The EPDS cutoff, severity bands and four-point direction rule are experiment settings.',
            'This artifact lacks the live pipeline key and cannot be used as evidence of real-world prediction accuracy.',
        ],
    }
    output.mkdir(parents=True, exist_ok=False)
    pd.concat([x, x_shift], ignore_index=True).to_csv(output / 'synthetic_features.csv', index=False)
    pd.concat([outcomes, outcomes_shift], ignore_index=True).to_csv(output / 'synthetic_outcomes.csv', index=False)
    (output / 'audit.json').write_text(json.dumps({
        'data_kind': DATA_KIND,
        'clinical_promotion_allowed': False,
        'generator_version': GENERATOR_VERSION,
        'seed': seed,
    }, indent=2) + '\n', encoding='utf-8')
    memberships = pd.concat([
        frame[['participant_id']].drop_duplicates().assign(partition=name)
        for name, frame in {**parts, 'shifted_test': shifted}.items()
    ], ignore_index=True)
    memberships.to_csv(output / 'synthetic_partitions.csv', index=False)
    (output / 'synthetic_report.json').write_text(json.dumps(report, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    joblib.dump({'data_kind': DATA_KIND, 'clinical_promotion_allowed': False,
                 'synthetic_experiment_models': models}, output / 'synthetic_experiment.joblib')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--participants', type=int, default=600)
    args = parser.parse_args()
    report = experiment(args.output_dir, args.seed, args.participants)
    for model_name, holdouts in report['models'].items():
        for holdout_name, result in holdouts.items():
            print(f'{model_name} {holdout_name}: MAE={result["mae_epds_points"]}, '
                  f'incident AUROC={result["incident_positive"]["auroc"]}, '
                  f'direction accuracy={result["symptom_direction"]["accuracy_percent"]}% (synthetic)')
