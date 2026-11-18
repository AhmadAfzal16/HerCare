from pathlib import Path

from fastapi.testclient import TestClient
import pandas as pd
import pytest

from app.main import app
from app.model_runtime import ModelRuntime
from app.recovery import RecoveryRequest, summarize
from app.sentiment import SentimentRequest, analyze, route_language
from scripts.sentiment_review import consensus
from training.sentiment_train import clean_rows
from training.event_features import build_event_features
from training.forecast_train import prepare
from training.train import train as legacy_train


def test_real_artifact_has_no_fabricated_clinical_confidence():
    runtime = ModelRuntime(Path(__file__).parents[1] / 'artifacts' / 'peri_dep_baseline.joblib')
    result = runtime.predict({'age': 28, 'parity': 2, 'education_level': 'Matric', 'household_type': 'joint',
                              'financial_strain': 0, 'support_quality': 1})
    assert 0 <= result.depression_probability <= 1
    assert result.confidence is None and result.validation_status == 'research_only'
    assert result.explanation_type == 'observed_context_not_model_attribution'


def test_recovery_route_daily_change_and_language_version_separation():
    body = {'as_of': '2026-10-08', 'observations': [
        {'entry_date': '2026-10-07', 'mood_rating': 3}, {'entry_date': '2026-10-08', 'mood_rating': 4}],
        'screenings': [
            {'instrument': 'phq9', 'version': 'v1', 'language': 'en', 'score': 18, 'completed_date': '2026-09-24'},
            {'instrument': 'phq9', 'version': 'v1', 'language': 'ur', 'score': 8, 'completed_date': '2026-10-08'}]}
    result = summarize(RecoveryRequest.model_validate(body))
    assert result['periods'][0]['relative_index_change_percent'] == pytest.approx(50)
    assert result['screening_changes'] == []
    assert result['periods'][1]['direction'] == 'insufficient_data'


def test_private_ml_endpoints_require_token_in_production(monkeypatch):
    monkeypatch.setenv('ENVIRONMENT', 'production')
    monkeypatch.setenv('ML_SERVICE_TOKEN', 'test-service-key')
    client = TestClient(app)
    assert client.post('/v1/recovery', json={'as_of': '2026-10-08'}).status_code == 401
    response = client.post('/v1/recovery', json={'as_of': '2026-10-08'}, headers={'Authorization': 'Bearer test-service-key'})
    assert response.status_code == 200
    assert response.json()['validation_status'] == 'descriptive_not_clinically_validated'
    assert client.post('/v1/text/sentiment', json={'text': 'hello'}).status_code == 401


def test_sentiment_cleanup_never_imputes_labels_and_excludes_conflicts():
    rows = [{'text': 'same text', 'label': label, 'language': 'en', 'source': 'fixture', 'license': 'CC0-1.0'}
            for label in ['positive', 'negative']]
    rows += [{'text': 'other text', 'label': 'neutral', 'language': 'en', 'source': 'fixture', 'license': 'CC0-1.0'},
             {'text': 'no truth', 'label': None, 'language': 'en', 'license': 'CC0-1.0'}]
    frame, audit = clean_rows(rows)
    assert frame.label.tolist() == ['neutral']
    assert audit['conflicting_label_rows_excluded'] == 2
    assert audit['invalid_or_missing_label_text_license_rows'] == 1


def test_consensus_requires_two_independent_complete_reviewers():
    row = {'reviews': [{'reviewer_id': 'a', 'sentiment': 'negative', 'distress': 'possible'},
                       {'reviewer_id': 'b', 'sentiment': 'negative', 'distress': 'possible'}]}
    assert consensus(row)['clinical_validation'] is False
    row['reviews'][1]['reviewer_id'] = 'a'
    assert consensus(row) is None


def test_sentiment_language_routing():
    assert route_language('میں بہتر محسوس کرتی ہوں') == 'ur'
    assert route_language('main bohat khush hun') == 'roman_ur'
    assert route_language('I feel better today') == 'en'


@pytest.mark.parametrize('text', ['I feel happy and calm today', 'main bohat khush hun', 'میں آج بہت خوش ہوں'])
def test_provisioned_sentiment_models_return_bounded_nondiagnostic_results(text):
    directory = Path(__file__).parents[1] / 'artifacts' / 'sentiment' / 'public_v2'
    if not all((directory / f'{language}.joblib').is_file() for language in ('en', 'ur', 'roman_ur')):
        pytest.skip('Public artifacts are provisioned by the reproducible training command')
    result = analyze(SentimentRequest(text=text))
    assert -1 <= result['score'] <= 1
    assert result['clinical_distress_probability'] is None
    assert result['clinical_validation'] is False


def test_source_event_revisions_are_selected_at_index_not_from_the_future():
    export = {'schema_version': 2, 'data_kind': 'real_consented_source_events', 'from': '2026-09-01', 'to': '2026-09-15',
        'participants': [{'participant_id': 'test-fixture-not-a-real-mother', 'research_consent': True,
                          'timezone': 'UTC', 'granted_at': '2026-09-01T00:00:00Z'}],
        'events': [{'participant_id': 'test-fixture-not-a-real-mother', 'source_record_id': 'mood-one', 'type': 'mood',
                    'date': '2026-09-14', 'performed_at': '2026-09-14T12:00:00Z',
                    'available_at': available, 'values': {'mood_rating': rating}}
                   for available, rating in [('2026-09-14T12:00:00Z', 2), ('2026-09-15T12:00:00Z', 5)]]}
    x, y, audit = build_event_features(export)
    assert x.iloc[0]['mood_rating_1d_mean'] == 2
    assert pd.isna(y.iloc[0]['future_phq9_score'])
    assert audit['clinical_promotion_allowed'] is False


@pytest.mark.parametrize('kind', ['real_cross_sectional_research', 'synthetic'])
def test_forecast_refuses_cross_sectional_and_synthetic_training(tmp_path, kind):
    import json
    (tmp_path / 'audit.json').write_text(json.dumps({'data_kind': kind}), encoding='utf-8')
    with pytest.raises(ValueError, match='retrospective or synthetic'):
        prepare(tmp_path, 'v1:en')


def test_legacy_trajectory_cannot_bypass_followup_validation(tmp_path):
    with pytest.raises(ValueError, match='Legacy trajectory training is disabled'):
        legacy_train(tmp_path / 'missing.csv', tmp_path / 'unsafe.joblib', 'trajectory')


def test_forecast_rejects_wrong_followup_horizon(tmp_path):
    import hashlib
    import json
    # Synthetic unit fixture tests the gate, never producing a trained artifact.
    audit = {'data_kind': 'real_consented_source_events', 'schema_version': 2,
        'extractor_version': 'source-event-features-v2', 'protected_export_provenance': True,
        'source_export': {'export_id': 'bb780b97-fbce-4a36-bc97-224dc9e36249', 'study_id': 'ENGINEERING-FIXTURE-ONLY',
                         'policy_version': 'research-aggregate-v1', 'from': '2026-08-01', 'to': '2026-09-30'},
        'source_export_sha256': 'e' * 64, 'pre_index_available_only': True, 'missing_outcomes_imputed': False,
        'clinical_promotion_allowed': False, 'split_group': 'participant_id', 'horizon_days': 14, 'tolerance_days': 3,
        'predictor_columns': ['age', 'latest_phq9_score', 'latest_phq9_age_days']}
    keys = {'participant_id': [f'unit-fixture-{i}' for i in range(120)],
            'index_at': ['2026-09-01T00:00:00Z'] * 120}
    pd.DataFrame({**keys, 'age': [28] * 120, 'latest_phq9_score': [5] * 120,
        'latest_phq9_version': ['v1:en'] * 120, 'latest_phq9_age_days': [1] * 120,
        'latest_phq9_at': ['2026-08-31T00:00:00Z'] * 120,
        'latest_phq9_available_at': ['2026-08-31T00:00:00Z'] * 120}).to_csv(tmp_path / 'features.csv', index=False)
    pd.DataFrame({**keys, 'future_phq9_score': [8, 12] * 60,
                  'future_phq9_version': ['v1:en'] * 120,
                  'future_phq9_at': ['2026-09-30T00:00:00Z'] * 120,
                  'future_phq9_available_at': ['2026-09-30T00:00:00Z'] * 120}).to_csv(tmp_path / 'outcomes.csv', index=False)
    audit['table_sha256'] = {name: hashlib.sha256((tmp_path / name).read_bytes()).hexdigest()
                            for name in ['features.csv', 'outcomes.csv']}
    (tmp_path / 'audit.json').write_text(json.dumps(audit), encoding='utf-8')
    with pytest.raises(ValueError, match='day-14'):
        prepare(tmp_path, 'v1:en')
