import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from app import community_moderation as module


def test_missing_model_fails_closed(monkeypatch, tmp_path):
    monkeypatch.setenv('COMMUNITY_MODEL_PATH', str(tmp_path / 'missing'))
    module.classifier.cache_clear()
    with pytest.raises(HTTPException) as error:
        module.moderate(module.ModerationRequest(text='A supportive message'))
    assert error.value.status_code == 503


def test_multilingual_triage_contract(monkeypatch):
    chunks = []
    def fake(text, candidate_labels, multi_label):
        chunks.append(text)
        return {'labels': candidate_labels, 'scores': [0.1, 0.2, 0.3, 0.4, 0.9]}
    monkeypatch.setattr(module, 'classifier', lambda: fake)
    result = module.moderate(module.ModerationRequest(text='امید ' * 200))
    assert chunks == ['امید ' * 200]
    assert result['scores']['support'] == 0.9
    assert result['policy_version'] == module.POLICY_VERSION
    assert result['clinical_validation'] is False
    assert result['full_text_processed'] is True
    with pytest.raises(ValidationError):
        module.ModerationRequest(text='x' * 2201)


def test_saturation_is_bounded():
    module._slot.acquire()
    try:
        with pytest.raises(HTTPException) as error:
            module.moderate(module.ModerationRequest(text='Hello'))
        assert error.value.status_code == 503
    finally:
        module._slot.release()


def test_community_endpoint_requires_service_token(monkeypatch):
    from app.main import moderate_community
    monkeypatch.setenv('ENVIRONMENT', 'production')
    monkeypatch.setenv('ML_SERVICE_TOKEN', 'test-service-token')
    with pytest.raises(HTTPException) as error:
        moderate_community(module.ModerationRequest(text='Hello'), None)
    assert error.value.status_code == 401


def test_community_never_allows_a_blank_internal_token(monkeypatch):
    from app.main import moderate_community
    monkeypatch.setenv('ENVIRONMENT', 'development')
    monkeypatch.delenv('ML_SERVICE_TOKEN', raising=False)
    with pytest.raises(HTTPException) as error:
        moderate_community(module.ModerationRequest(text='Hello'), None)
    assert error.value.status_code == 503


def test_model_windows_process_overflow_and_fail_on_nonfinite_logits():
    import numpy as np
    from types import SimpleNamespace
    classifier = object.__new__(module.OnnxClassifier)
    classifier.entailment = 0
    classifier.contradiction = 2
    tail = SimpleNamespace(ids=[99], attention_mask=[1], type_ids=[0])
    original = SimpleNamespace(ids=[2], attention_mask=[1], type_ids=[0], overflowing=[tail])
    classifier.tokenizer = SimpleNamespace(encode_batch=lambda _: [original] * 5)
    seen = []
    def infer(_, inputs):
        seen.extend(inputs['input_ids'][:, 0].tolist())
        return [np.asarray([[10 if row[0] == 99 else -10, 0, 0]
                           for row in inputs['input_ids']], dtype=float)]
    classifier.session = SimpleNamespace(get_inputs=lambda: [SimpleNamespace(name='input_ids')], run=infer)
    result = classifier('Long text', list(module.LABELS.values()), True)
    assert len(seen) == 10 and seen.count(99) == 5
    assert all(score > .99 for score in result['scores'])
    classifier.session.run = lambda _, inputs: [np.full((len(inputs['input_ids']), 3), np.nan)]
    with pytest.raises(ValueError):
        classifier('Long text', list(module.LABELS.values()), True)


def test_excessive_token_work_fails_instead_of_truncating():
    from types import SimpleNamespace
    classifier = object.__new__(module.OnnxClassifier)
    original = SimpleNamespace(overflowing=[object()] * 40)
    classifier.tokenizer = SimpleNamespace(encode_batch=lambda _: [original] * 5)
    with pytest.raises(HTTPException) as error:
        classifier('Long text', list(module.LABELS.values()), True)
    assert error.value.status_code == 422


@pytest.mark.parametrize('scores', [[0.1] * 4, [float('nan')] * 5, [float('inf')] * 5,
                                    [-0.1] * 5, [1.01] * 5, [True] * 5, ['0.1'] * 5])
def test_bad_model_scores_fail_closed_and_release_slot(monkeypatch, scores):
    monkeypatch.setattr(module, 'classifier', lambda: lambda *a, **k:
                        {'labels': list(module.LABELS.values()), 'scores': scores})
    with pytest.raises(HTTPException) as error:
        module.moderate(module.ModerationRequest(text='Useful message'))
    assert error.value.status_code == 503
    assert module._slot.acquire(blocking=False)
    module._slot.release()


@pytest.mark.parametrize('text', ['  ', '\x00hi', 'x' * 2201])
def test_invalid_text(text):
    with pytest.raises(ValidationError):
        module.ModerationRequest(text=text)


def test_duplicate_model_labels_fail_closed(monkeypatch):
    monkeypatch.setattr(module, 'classifier', lambda: lambda *a, **k:
                        {'labels': [list(module.LABELS.values())[0]] * 5, 'scores': [0.5] * 5})
    with pytest.raises(HTTPException):
        module.moderate(module.ModerationRequest(text='Useful message'))


def test_readiness_endpoint_is_private(monkeypatch):
    from fastapi.testclient import TestClient
    from app.main import app
    monkeypatch.setenv('ENVIRONMENT', 'production')
    monkeypatch.setenv('ML_SERVICE_TOKEN', 'fixture-only-token')
    monkeypatch.setattr(module, 'classifier', lambda: object())
    with TestClient(app) as client:
        assert client.get('/v1/community/ready').status_code == 401
        response = client.get('/v1/community/ready', headers={'Authorization': 'Bearer fixture-only-token'})
        assert response.status_code == 200
        assert response.headers['cache-control'] == 'private, no-store'
        assert response.json()['status'] == 'ready'
        assert 'path' not in str(response.json())


def test_provenance_requires_exact_revision_and_checksums(tmp_path, monkeypatch):
    import json
    directory = tmp_path / 'weights'
    (directory / 'onnx').mkdir(parents=True)
    files = ['onnx/model.onnx', 'onnx/tokenizer.json', 'onnx/config.json']
    for name in files:
        (directory / name).write_bytes(b'engineering-fixture')
    manifest = {'repository': module.REPOSITORY, 'revision': module.REVISION,
                'runtime': 'onnx-cpu', 'license': 'MIT',
                'sha256': {name: module.checksum(directory / name) for name in files}}
    monkeypatch.setattr(module, 'SOURCE_HASHES', dict(manifest['sha256']))
    (directory / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    assert module.verified_files(directory)['revision'] == module.REVISION
    (directory / files[0]).write_bytes(b'tampered')
    with pytest.raises(HTTPException):
        module.verified_files(directory)
    manifest['sha256'][files[0]] = module.checksum(directory / files[0])
    (directory / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    with pytest.raises(HTTPException):
        module.verified_files(directory)
