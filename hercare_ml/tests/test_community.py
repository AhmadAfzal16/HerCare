import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from app import community_moderation as module


def test_missing_model_fails_closed(monkeypatch):
    monkeypatch.delenv('COMMUNITY_MODEL_PATH', raising=False)
    module.classifier.cache_clear()
    with pytest.raises(HTTPException) as error:
        module.moderate(module.ModerationRequest(text='A supportive message'))
    assert error.value.status_code == 503


def test_chunked_multilingual_triage(monkeypatch):
    chunks = []
    def fake(text, candidate_labels, multi_label):
        chunks.append(text)
        return {'labels': candidate_labels, 'scores': [0.1, 0.2, 0.3, 0.4, 0.9]}
    monkeypatch.setattr(module, 'classifier', lambda: fake)
    result = module.moderate(module.ModerationRequest(text='امید ' * 200))
    assert len(chunks) > 1
    assert result['scores']['support'] == 0.9
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
