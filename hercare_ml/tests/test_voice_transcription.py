from __future__ import annotations
import io
import wave
from types import SimpleNamespace
import numpy as np
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from app.main import app
from app import voice_transcription as voice

def wav(seconds=1, silence=False):
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(16000)
        samples = np.zeros(int(16000 * seconds), dtype=np.int16) if silence else (
            np.sin(np.arange(int(16000 * seconds)) * 2 * np.pi * 220 / 16000) * 8000).astype(np.int16)
        stream.writeframes(samples.tobytes())
    return buffer.getvalue()

def test_real_decoder_caps_decoded_duration_and_rejects_invalid_audio():
    assert voice.decode_bounded(wav()).shape == (16000,)
    for data in [b"RIFF-fake", wav(seconds=0.1), wav(seconds=66)]:
        with pytest.raises(HTTPException) as error:
            voice.decode_bounded(data)
        assert error.value.status_code == 422

def test_silence_never_becomes_invented_words_or_mood(monkeypatch):
    monkeypatch.setattr(voice, "runtime", lambda: pytest.fail("silence must not load the model"))
    result = voice.transcribe(wav(silence=True), "audio/wav", "ur")
    assert result["status"] == "no_speech" and result["text"] == ""
    assert result["review_required"] is True

@pytest.mark.parametrize("language,text", [("en", "I feel supported."), ("ur", "میں بہتر محسوس کر رہی ہوں")])
def test_asr_only_produces_reviewable_bounded_drafts(monkeypatch, language, text):
    options = {}
    class Model:
        def transcribe(self, data, **kwargs):
            options.update(kwargs)
            return iter([SimpleNamespace(text=text, no_speech_prob=.1, avg_logprob=-.1, compression_ratio=1.1)]), None
    monkeypatch.setattr(voice, "runtime", lambda: (Model(), "test-only"))
    result = voice.transcribe(wav(), "audio/wav", language)
    assert result["text"] == text and result["status"] == "draft"
    assert result["review_required"] is True
    assert options["language"] == language and options["task"] == "transcribe"
    assert options["vad_filter"] and not options["condition_on_previous_text"]
    assert "contains_danger" not in result and "depression_probability" not in result

def test_low_confidence_speech_is_not_reported_as_neutral_sentiment(monkeypatch):
    model = SimpleNamespace(transcribe=lambda *a, **k: (
        iter([SimpleNamespace(text="hallucinated words", no_speech_prob=.95, avg_logprob=-3, compression_ratio=3)]), None))
    monkeypatch.setattr(voice, "runtime", lambda: (model, "test-only"))
    assert voice.transcribe(wav(), "audio/wav", "en")["status"] == "no_speech"

def test_worker_backpressure_is_explicit_and_releases_after_failure(monkeypatch):
    voice.slots.acquire()
    try:
        with pytest.raises(HTTPException) as error:
            voice.transcribe(wav(), "audio/wav", "en")
        assert error.value.status_code == 429
    finally:
        voice.slots.release()
    with pytest.raises(HTTPException):
        voice.transcribe(b"not audio", "audio/wav", "en")
    assert voice.slots.acquire(blocking=False)
    voice.slots.release()

def test_private_endpoint_authentication_and_upload_bounds(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("ML_SERVICE_TOKEN", "synthetic-private-voice-test")
    client = TestClient(app)
    assert client.post("/v1/audio/transcribe", content=wav(), headers={"Content-Type": "audio/wav"}).status_code == 401
    headers = {"Authorization": "Bearer synthetic-private-voice-test", "Content-Type": "audio/wav", "X-Voice-Language": "ur"}
    assert client.post("/v1/audio/transcribe", content=b"x" * (voice.MAX_BYTES + 1), headers=headers).status_code == 413
    assert client.post("/v1/audio/transcribe", content=wav(), headers={**headers, "X-Voice-Language": "ar"}).status_code == 422
    result = client.post("/v1/audio/transcribe", content=wav(silence=True), headers=headers)
    assert result.status_code == 200 and result.json()["status"] == "no_speech"

def test_absent_model_does_not_download_at_request_time(monkeypatch, tmp_path):
    monkeypatch.setenv("VOICE_MODEL_PATH", str(tmp_path))
    with pytest.raises(HTTPException) as error:
        voice.model_path()
    assert error.value.status_code == 503
