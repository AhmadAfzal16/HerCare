"""Server-only, bounded ASR. Drafts are not verified clinical/safety measurements."""
from __future__ import annotations

import hashlib
import io
import json
import os
import pathlib
import threading
from functools import lru_cache

import numpy as np
from fastapi import HTTPException

MAX_BYTES = 4 * 1024 * 1024
MAX_SECONDS = 65  # recording stops at 60s; small encoder/container tolerance
SAMPLE_RATE = 16000
slots = threading.BoundedSemaphore(1)
FORMATS = {"audio/wav", "audio/mp4", "audio/mpeg"}


def model_path() -> pathlib.Path:
    default = pathlib.Path(__file__).parents[1] / "artifacts" / "voice" / "small"
    path = pathlib.Path(os.getenv("VOICE_MODEL_PATH", str(default))).resolve()
    if os.getenv("VOICE_ASR_ENABLED", "true").lower() != "true":
        raise HTTPException(503, "Voice transcription is disabled")
    if not all((path / name).is_file() for name in ("model.bin", "config.json", "tokenizer.json", "vocabulary.txt", "manifest.json")):
        raise HTTPException(503, "Voice model has not been provisioned")
    return path


@lru_cache(maxsize=1)
def runtime():
    path = model_path()
    try:
        manifest = json.loads((path / "manifest.json").read_text(encoding="utf-8"))
        if manifest["repository"] != "Systran/faster-whisper-small" or manifest["license"] != "MIT":
            raise ValueError("Unsupported model manifest")
        for name in ("model.bin", "config.json", "tokenizer.json", "vocabulary.txt"):
            digest = hashlib.sha256()
            with (path / name).open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != manifest["sha256"][name]:
                raise ValueError("Model integrity failure")
        from faster_whisper import WhisperModel
        threads = int(os.getenv("VOICE_CPU_THREADS", "2"))
        if not 1 <= threads <= 8:
            raise ValueError("Invalid voice thread configuration")
        model = WhisperModel(str(path), device="cpu", compute_type="int8",
                             cpu_threads=threads, num_workers=1, local_files_only=True)
        return model, "whisper-small-ct2:" + manifest["revision"][:12]
    except (ImportError, OSError, ValueError, KeyError, RuntimeError) as error:
        raise HTTPException(503, "Voice model/runtime is unavailable") from error


def decode_bounded(audio: bytes) -> np.ndarray:
    """Decode only memory data; cap decoded duration before allocating whole input."""
    try:
        import av
        chunks, samples = [], 0
        with av.open(io.BytesIO(audio), mode="r") as container:
            if not container.streams.audio:
                raise ValueError("No audio stream")
            stream = container.streams.audio[0]
            resampler = av.AudioResampler(format="fltp", layout="mono", rate=SAMPLE_RATE)
            for frame in container.decode(stream):
                if frame.samples > 1_000_000 or frame.sample_rate > 192000:
                    raise ValueError("Unsupported frame")
                for converted in resampler.resample(frame):
                    values = converted.to_ndarray().reshape(-1)
                    samples += values.size
                    if samples > MAX_SECONDS * SAMPLE_RATE:
                        raise HTTPException(422, "Use a voice clip of no more than 60 seconds")
                    chunks.append(values)
            for converted in resampler.resample(None):
                values = converted.to_ndarray().reshape(-1)
                samples += values.size
                if samples > MAX_SECONDS * SAMPLE_RATE:
                    raise HTTPException(422, "Use a voice clip of no more than 60 seconds")
                chunks.append(values)
        if samples < SAMPLE_RATE // 5:
            raise ValueError("Empty/too short audio")
        result = np.concatenate(chunks).astype(np.float32, copy=False)
        if not np.isfinite(result).all():
            raise ValueError("Nonfinite audio")
        return result
    except HTTPException:
        raise
    except ImportError as error:
        raise HTTPException(503, "Audio decoder is unavailable") from error
    except Exception as error:
        raise HTTPException(422, "Audio could not be decoded safely") from error


def transcribe(audio: bytes, content_type: str, language: str) -> dict:
    if os.getenv("VOICE_ASR_ENABLED", "true").lower() != "true":
        raise HTTPException(503, "Voice transcription is disabled")
    if content_type not in FORMATS or language not in {"en", "ur"}:
        raise HTTPException(422, "Unsupported voice format or language")
    if not 1 <= len(audio) <= MAX_BYTES:
        raise HTTPException(413, "Voice clip exceeds the upload limit")
    if not slots.acquire(blocking=False):
        raise HTTPException(429, "Voice worker is busy; retry later")
    try:
        waveform = decode_bounded(audio)
        if float(np.max(np.abs(waveform))) < 0.001:
            return {"status": "no_speech", "text": "", "language": language,
                    "model_version": "silence-filter-v1", "review_required": True}
        model, version = runtime()
        segments, _ = model.transcribe(waveform, language=language, task="transcribe",
            beam_size=3, temperature=0, vad_filter=True, condition_on_previous_text=False,
            vad_parameters={"min_silence_duration_ms": 500}, max_new_tokens=256)
        texts = []
        for i, segment in enumerate(segments):
            if i >= 130:
                raise HTTPException(422, "Transcript is too large to review")
            # Low-confidence/no-speech chunks are never fabricated as neutral mood.
            if segment.no_speech_prob > 0.6 or segment.avg_logprob < -1.0 or segment.compression_ratio > 2.4:
                continue
            text = segment.text.strip()
            if text:
                texts.append(text)
            if sum(len(item) for item in texts) + len(texts) > 5000:
                raise HTTPException(422, "Transcript is too large to review")
        text = " ".join(texts)
        return {"status": "draft" if text else "no_speech", "text": text,
                "language": language, "model_version": version, "review_required": True}
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(503, "Voice transcription failed; original audio is unchanged") from error
    finally:
        slots.release()
