"""Fabricated engineering fixtures only: never evidence of clinical performance."""
import hashlib
import json

import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression

from training.forecast_train import (ForecastSpec, build_pipeline, grouped_folds,
                                     nested_group_evaluation, prepare, train)
from training.longitudinal_features import build_features
from training.event_features import build_event_features


def tables(tmp_path, *, instrument='phq9', baseline=5, future=None):
    """Pretend protected tables ONLY to exercise gates, not for exported models."""
    count = 120
    baseline_at = '2026-09-13T00:00:00Z'
    keys = {'participant_id': [f'engineering-fixture-{i}' for i in range(count)],
            'index_at': ['2026-09-15T00:00:00Z'] * count}
    x = pd.DataFrame({**keys, 'age': [28] * count,
        f'latest_{instrument}_score': [baseline] * count, f'latest_{instrument}_age_days': [2] * count,
        f'latest_{instrument}_version': ['v1:en'] * count, f'latest_{instrument}_at': [baseline_at] * count,
        f'latest_{instrument}_available_at': [baseline_at] * count,
        'mood_rating_14d_mean': [2, 4] * 60, 'mood_rating_14d_coverage': [.5] * count,
        'sleep_minutes_14d_mean': [None] * count, 'sleep_minutes_14d_coverage': [0] * count})
    y = pd.DataFrame({**keys, f'future_{instrument}_score': future if future is not None else [7, 14] * 60,
        f'future_{instrument}_version': ['v1:en'] * count,
        f'future_{instrument}_at': ['2026-09-29T00:00:00Z'] * count,
        f'future_{instrument}_available_at': ['2026-09-29T00:00:00Z'] * count})
    audit = {'data_kind': 'real_consented_source_events', 'schema_version': 2,
        'extractor_version': 'source-event-features-v2', 'protected_export_provenance': True,
        'source_export': {'export_id': 'bb780b97-fbce-4a36-bc97-224dc9e36249', 'study_id': 'ENGINEERING-FIXTURE-NOT-REAL',
                          'policy_version': 'research-aggregate-v1', 'from': '2026-09-01', 'to': '2026-09-30'},
        'source_export_sha256': 'e' * 64, 'pre_index_available_only': True, 'missing_outcomes_imputed': False,
        'clinical_promotion_allowed': False, 'split_group': 'participant_id', 'horizon_days': 14, 'tolerance_days': 3,
        'predictor_columns': ['age', f'latest_{instrument}_score', f'latest_{instrument}_age_days',
                             'mood_rating_14d_mean', 'mood_rating_14d_coverage',
                             'sleep_minutes_14d_mean', 'sleep_minutes_14d_coverage']}
    save(tmp_path, x, y, audit)
    return x, y, audit


def save(directory, x, y, audit):
    x.to_csv(directory / 'features.csv', index=False)
    y.to_csv(directory / 'outcomes.csv', index=False)
    audit['table_sha256'] = {name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
                            for name in ['features.csv', 'outcomes.csv']}
    (directory / 'audit.json').write_text(json.dumps(audit), encoding='utf-8')


def test_incident_cohort_requires_negative_baseline_and_actual_future(tmp_path):
    x, y, audit = tables(tmp_path)
    x.loc[0, 'latest_phq9_score'] = 12  # Already positive is not an incident case.
    y.loc[1, 'future_phq9_score'] = np.nan  # No follow-up is not a negative label.
    y.loc[2, 'future_phq9_version'] = 'v1:ur'
    save(tmp_path, x, y, audit)
    frame, target, columns, excluded = prepare(tmp_path, ForecastSpec('phq9', 'v1:en', 10))
    assert len(frame) == 117 and excluded == 3
    assert set(target) == {0, 1}
    assert 'latest_phq9_score' in columns and 'sleep_minutes_14d_mean' in columns
    assert frame.sleep_minutes_14d_mean.isna().all()
    assert not any(column.startswith('future_') for column in columns)


def test_symptomatic_worsening_is_not_called_nonimprovement_or_remission(tmp_path):
    tables(tmp_path, baseline=15, future=[12, 17] * 60)
    spec = ForecastSpec('phq9', 'v1:en', 10, task='future_worsening', minimum_change_points=2)
    frame, target, _, _ = prepare(tmp_path, spec)
    assert target.tolist() == frame.future_phq9_score.sub(frame.latest_phq9_score).ge(2).astype(int).tolist()
    assert frame.latest_phq9_score.eq(15).all()


def test_epds_is_a_separate_exact_version_target(tmp_path):
    tables(tmp_path, instrument='epds', baseline=8, future=[9, 14] * 60)
    frame, target, columns, _ = prepare(tmp_path, ForecastSpec('epds', 'v1:en', 13))
    assert target.tolist() == frame.future_epds_score.ge(13).astype(int).tolist()
    assert 'latest_epds_score' in columns and 'latest_phq9_score' not in columns


@pytest.mark.parametrize('mutation,message', [
    (lambda x, y, a: a.update(protected_export_provenance=False), 'Protected'),
    (lambda x, y, a: a['predictor_columns'].append('future_phq9_score'), 'whitelist'),
    (lambda x, y, a: x.__setitem__('age', float('inf')), 'finite'),
    (lambda x, y, a: y.__setitem__('future_phq9_score', 7.5), 'finite'),
    (lambda x, y, a: y.__setitem__('future_phq9_at', '2026-09-30T00:00:00'), 'timezone'),
    (lambda x, y, a: (y.__setitem__('future_phq9_at', '2026-10-15T00:00:00Z'),
                      y.__setitem__('future_phq9_available_at', '2026-10-15T00:00:00Z'),
                      a['source_export'].update(to='2026-10-30')), 'day-14'),
    (lambda x, y, a: x.__setitem__('latest_phq9_available_at', '2026-09-16T00:00:00Z'), 'post-index'),
    (lambda x, y, a: x.__setitem__('latest_phq9_age_days', 1), 'freshness'),
    (lambda x, y, a: x.__setitem__('latest_phq9_version', 'v2:en'), 'pilot minimum'),
    (lambda x, y, a: x.__setitem__('latest_phq9_at', '2026-08-25T00:00:00Z'), 'freshness'),
])
def test_invalid_leaking_stale_or_untrusted_tables_fail_closed(tmp_path, mutation, message):
    x, y, audit = tables(tmp_path)
    mutation(x, y, audit)
    save(tmp_path, x, y, audit)
    with pytest.raises(ValueError, match=message):
        prepare(tmp_path, ForecastSpec('phq9', 'v1:en', 10))


def test_tables_changed_after_extraction_are_rejected(tmp_path):
    x, _, _ = tables(tmp_path)
    x.loc[0, 'age'] = 29
    x.to_csv(tmp_path / 'features.csv', index=False)
    with pytest.raises(ValueError, match='changed after'):
        prepare(tmp_path, 'v1:en')


def test_no_labels_never_train_or_create_artifact(tmp_path):
    x, y, audit = tables(tmp_path)
    y.future_phq9_score = np.nan
    save(tmp_path, x, y, audit)
    output = tmp_path / 'must-not-exist'
    with pytest.raises(ValueError, match='actual eligible follow-up'):
        train(tmp_path, output, ForecastSpec('phq9', 'v1:en', 10))
    assert not output.exists()


def test_secondary_scores_only_with_explicit_exact_version_and_freshness(tmp_path):
    x, y, audit = tables(tmp_path)
    for suffix, value in [('score', 9), ('age_days', 2), ('version', 'v1:ur'),
                          ('at', '2026-09-13T00:00:00Z'), ('available_at', '2026-09-13T00:00:00Z')]:
        x[f'latest_epds_{suffix}'] = value
    audit['predictor_columns'] += ['latest_epds_score', 'latest_epds_age_days']
    save(tmp_path, x, y, audit)
    _, _, columns, _ = prepare(tmp_path, ForecastSpec('phq9', 'v1:en', 10))
    assert 'latest_epds_score' not in columns
    frame, _, columns, _ = prepare(tmp_path, ForecastSpec('phq9', 'v1:en', 10, secondary_version_language='v1:en'))
    assert 'latest_epds_score' in columns and frame.latest_epds_score.isna().all()


def test_imputation_is_fit_fold_only_and_all_missing_has_indicator():
    fit = pd.DataFrame({'age': [20, 40], 'sleep_minutes_14d_mean': [np.nan, np.nan]})
    pipeline = build_pipeline(list(fit), LogisticRegression(solver='liblinear'))
    pipeline.fit(fit, [0, 1])
    imputer = pipeline.named_steps['preprocess'].named_transformers_['numeric'].named_steps['impute']
    assert imputer.statistics_[0] == 30
    assert imputer.indicator_.features_.tolist() == [1]
    assert np.isfinite(pipeline.named_steps['preprocess'].transform(pd.DataFrame({'age': [100], 'sleep_minutes_14d_mean': [np.nan]}))).all()
    assert imputer.statistics_[0] == 30  # Validation did not alter the median.


def test_full_nested_cv_covers_all_rows_and_held_out_participants():
    # Small classifiers and fabricated data verify plumbing, not medical accuracy.
    groups = pd.Series(np.repeat([f'fixture-{i}' for i in range(90)], 2))
    target = pd.Series(np.repeat(np.arange(90) % 2, 2))
    frame = pd.DataFrame({'participant_id': groups, 'age': 20 + np.arange(180) % 15,
                          'mood_rating_14d_mean': [np.nan if i % 11 == 0 else 1 + i % 5 for i in range(180)]})
    candidates = [
        ('logistic', 'unit-small', LogisticRegression(C=.1, solver='liblinear'), 'balanced'),
        ('forest', 'unit-small', RandomForestClassifier(n_estimators=5, max_depth=2, min_samples_leaf=4, random_state=1), 'balanced'),
        ('boosting', 'unit-small', GradientBoostingClassifier(n_estimators=5, max_depth=1, random_state=1), 'none')]
    report, probabilities = nested_group_evaluation(frame, target, ['age', 'mood_rating_14d_mean'],
        outer_splits=3, inner_splits=2, calibration_splits=3, candidates=candidates)
    assert len(report['folds']) == 3 and all(fold['participant_disjoint'] for fold in report['folds'])
    assert set(probabilities) == {'logistic', 'forest', 'boosting', 'inner_selected_policy'}
    assert all(len(values) == 180 and np.isfinite(values).all() for values in probabilities.values())
    assert report['threshold'] == .5 and report['selection_metric'] == 'inner ROC AUC only'
    for values in report['out_of_fold_metrics'].values():
        assert {'sensitivity', 'specificity', 'balanced_accuracy', 'roc_auc', 'brier_score', 'calibration_bins'} <= set(values)
    for fit, test in grouped_folds(target, groups, 3, 42, 'test assertion'):
        assert not set(groups.iloc[fit]) & set(groups.iloc[test])


def test_one_class_or_too_few_class_groups_refuses_nested_cv():
    y, groups = pd.Series([0] * 8 + [1] * 2), pd.Series([f'g-{i}' for i in range(10)])
    with pytest.raises(ValueError, match='class-specific'):
        grouped_folds(y, groups, 3, 42, 'outer')


def test_clock_features_wrap_midnight_without_arithmetic_mean():
    export = {'schema_version': 1, 'data_kind': 'real_consented_observations',
        'participants': [{'participant_id': 'fixture-only', 'research_consent': True, 'timezone': 'UTC'}],
        'indexes': [{'participant_id': 'fixture-only', 'index_at': '2026-09-15T00:00:00Z'}],
        'daily_observations': [{'participant_id': 'fixture-only', 'date': date, 'available_at': date + 'T23:00:00Z',
            'bedtime_local_minutes': clock, 'recorded_sleep_quality': 3}
            for date, clock in [('2026-09-13', 1380), ('2026-09-14', 60)]], 'assessments': []}
    x, _, _ = build_features(export)
    assert x.iloc[0].bedtime_local_minutes_14d_cos_mean == pytest.approx(np.cos(np.pi / 12))
    assert x.iloc[0].bedtime_local_minutes_14d_sin_mean == pytest.approx(0)
    assert x.iloc[0].bedtime_local_minutes_14d_coverage == 2 / 14
    assert 'bedtime_local_minutes_14d_mean' not in x
    assert x.iloc[0].recorded_sleep_quality_14d_mean == 3


def event_export():
    return {'schema_version': 2, 'data_kind': 'real_consented_source_events',
        'export_id': 'bb780b97-fbce-4a36-bc97-224dc9e36249', 'policy_version': 'research-aggregate-v1',
        'study_id': 'ENGINEERING-FIXTURE-ONLY', 'from': '2026-09-01', 'to': '2026-09-16',
        'participants': [{'participant_id': 'fixture-only', 'research_consent': True,
                          'timezone': 'UTC', 'granted_at': '2026-09-01T12:00:00Z'}],
        'events': [{'participant_id': 'fixture-only', 'source_record_id': 'fixture-' + kind, 'type': kind,
            'date': '2026-09-14', 'performed_at': '2026-09-14T12:00:00Z', 'available_at': '2026-09-14T12:00:00Z',
            'values': values} for kind, values in [
                ('sleep', {'sleep_minutes': 420, 'sleep_quality': 4, 'bedtime_local_minutes': 1380, 'wake_local_minutes': 360}),
                ('text_signal', {'sentiment_score': -.7}), ('prediction', {'depression_probability': .99})]]}


def test_real_export_uuid_clock_fields_and_nonpredictor_events():
    x, _, audit = build_event_features(event_export())
    assert x.index_at.tolist() == ['2026-09-16T00:00:00+00:00']  # Full fourteen days after afternoon opt-in.
    assert audit['protected_export_provenance'] is True
    assert audit['recognized_nonpredictor_events_excluded'] == {'prediction': 1, 'text_signal': 1}
    assert x.iloc[0].recorded_sleep_quality_14d_mean == 4
    assert x.iloc[0].bedtime_local_minutes_14d_cos_mean == pytest.approx(np.cos(np.pi / 12))
    assert not any('sentiment' in name or 'probability' in name for name in audit['predictor_columns'])
    assert pd.isna(x.iloc[0].sleep_quality_14d_mean)  # Sleep record never replaces mood-check-in sleep quality.


def test_unknown_event_and_ambiguous_screening_revision_fail_closed():
    export = event_export()
    export['events'][0]['type'] = 'unrecognized'
    with pytest.raises(ValueError, match='Unknown source'):
        build_event_features(export)
    export = event_export()
    event = export['events'][0]
    event.update(type='screening', values={'instrument': 'phq9', 'version': 'v1', 'language': 'en', 'score': 5})
    export['events'].append({**event, 'available_at': '2026-09-15T00:00:00Z',
                            'values': {**event['values'], 'score': 20}})
    with pytest.raises(ValueError, match='immutable completed'):
        build_event_features(export)
