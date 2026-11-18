"""Private CPU peer-content triage, never diagnosis or publication approval.

Only checksum-provisioned local ONNX/tokenizer files are loaded. No request can
download weights, run remote Python, read journals or notify a guardian.
"""
from __future__ import annotations

from functools import lru_cache
import hashlib
import json
import math
import os
from pathlib import Path
from threading import BoundedSemaphore

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator

POLICY_VERSION = "community-triage-2026-10-v2"
REPOSITORY = "MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli"
REVISION = "0a71e92a985b6e1ad1828cf67ce9c459639c1dca"
MODEL_VERSION = "minilm-l6-" + REVISION[:12] + "-onnx-v1"
DEFAULT_PATH = Path(__file__).parents[1] / "artifacts" / "community" / "minilm_v1"
LABELS = {
    "self_harm": "self-harm or suicide",
    "bullying": "bullying, abuse or harassment",
    "spam": "spam or advertising",
    "medical_advice": "instructions about medication or medical treatment",
    "support": "kind peer support and personal recovery experiences",
}
MAX_SEQUENCE = 256
MAX_PAIRS = 160
SOURCE_HASHES = {
    "onnx/model.onnx": "79f8cda2b1230585a95ea0514a6f1bd21c5c986ba0529bb3261213a3e195fa6e",
    "onnx/tokenizer.json": "b2116c05e7305eea30394284760789681c5b3440dd4cd9a8c77539da68f9e8a6",
    "onnx/config.json": "e08b628c4d46c8601dda34ddb40a7857e5961870b80482382d420db6dfb6e00e",
}
_slot = BoundedSemaphore(1)


class ModerationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(min_length=2, max_length=2200)

    @field_validator("text")
    @classmethod
    def nonempty(cls, value: str) -> str:
        if len(value.strip()) < 2 or "\x00" in value:
            raise ValueError("Community text must contain at least two characters")
        return value


def checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verified_files(directory: Path) -> dict:
    """Verify on cold start, not each inference; files must be mounted read-only."""
    try:
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        if (manifest["repository"] != REPOSITORY or manifest["revision"] != REVISION
                or manifest["runtime"] != "onnx-cpu" or manifest["license"] != "MIT"):
            raise ValueError("Unreviewed model provenance")
        for name in ("onnx/model.onnx", "onnx/tokenizer.json", "onnx/config.json"):
            file = (directory / name).resolve()
            if not file.is_relative_to(directory.resolve()) or not file.is_file():
                raise ValueError("Missing or unsafe model file")
            if manifest["sha256"][name] != SOURCE_HASHES[name] or checksum(file) != SOURCE_HASHES[name]:
                raise ValueError("Model file checksum mismatch")
        return manifest
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise HTTPException(503, "Community model provenance is unavailable or invalid") from error


class OnnxClassifier:
    def __init__(self, directory: Path):
        verified_files(directory)
        import onnxruntime as ort
        from tokenizers import Tokenizer
        config = json.loads((directory / "onnx/config.json").read_text(encoding="utf-8"))
        labels = {name.lower(): int(index) for index, name in config["id2label"].items()}
        self.entailment = labels["entailment"]
        self.contradiction = labels["contradiction"]
        threads = int(os.getenv("COMMUNITY_CPU_THREADS", "2"))
        if not 1 <= threads <= 8:
            raise ValueError("Community CPU threads must be 1 through 8")
        options = ort.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        self.session = ort.InferenceSession(str(directory / "onnx/model.onnx"),
                                           sess_options=options, providers=["CPUExecutionProvider"])
        self.tokenizer = Tokenizer.from_file(str(directory / "onnx/tokenizer.json"))
        self.tokenizer.enable_truncation(MAX_SEQUENCE, stride=48, strategy="only_first")
        self.tokenizer.enable_padding(pad_id=int(config["pad_token_id"]), pad_token="<pad>")
        self.version = MODEL_VERSION

    def __call__(self, text: str, candidate_labels: list[str], multi_label: bool) -> dict:
        import numpy as np
        if not multi_label or len(candidate_labels) != len(LABELS):
            raise ValueError("Unsupported classification contract")
        encoded = self.tokenizer.encode_batch([(text, "This text is about " + label + ".")
                                               for label in candidate_labels])
        # Preserve every premise token via overlapping overflow windows, including
        # Urdu subword-heavy text. A post's tail is never silently truncated.
        pairs = [(index, window) for index, encoding in enumerate(encoded)
                 for window in (encoding, *encoding.overflowing)]
        if len(pairs) > MAX_PAIRS:
            raise HTTPException(422, "Community text exceeds the bounded token budget")
        scores = [0.0] * len(candidate_labels)
        for start in range(0, len(pairs), 5):
            batch = pairs[start:start + 5]
            width = max(len(window.ids) for _, window in batch)
            inputs = {}
            for input_meta in self.session.get_inputs():
                name = input_meta.name
                if name == "input_ids":
                    rows = [window.ids + [1] * (width - len(window.ids)) for _, window in batch]
                elif name == "attention_mask":
                    rows = [window.attention_mask + [0] * (width - len(window.ids)) for _, window in batch]
                elif name == "token_type_ids":
                    rows = [window.type_ids + [0] * (width - len(window.ids)) for _, window in batch]
                else:
                    raise ValueError("Unexpected ONNX input")
                inputs[name] = np.asarray(rows, dtype=np.int64)
            logits = np.asarray(self.session.run(None, inputs)[0])
            if logits.shape != (len(batch), 3) or not np.isfinite(logits).all():
                raise ValueError("Invalid ONNX logits")
            difference = np.clip(logits[:, self.contradiction] - logits[:, self.entailment], -80, 80)
            probabilities = 1 / (1 + np.exp(difference))
            for (index, _), probability in zip(batch, probabilities):
                scores[index] = max(scores[index], float(probability))
        return {"labels": candidate_labels, "scores": scores}


@lru_cache(maxsize=1)
def classifier():
    directory = Path(os.getenv("COMMUNITY_MODEL_PATH", str(DEFAULT_PATH))).resolve()
    try:
        return OnnxClassifier(directory)
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(503, "Community moderation model is unavailable") from error


def metadata() -> dict:
    return {"model_version": MODEL_VERSION, "policy_version": POLICY_VERSION,
            "runtime": "onnx-cpu", "clinical_validation": False, "full_text_processed": True}


def ready() -> dict:
    if not _slot.acquire(blocking=False):
        raise HTTPException(503, "Community moderation is busy")
    try:
        classifier()
        return {"status": "ready", **metadata()}
    finally:
        _slot.release()


def moderate(request: ModerationRequest) -> dict:
    if not _slot.acquire(blocking=False):
        raise HTTPException(503, "Community moderation is busy")
    try:
        result = classifier()(request.text, candidate_labels=list(LABELS.values()), multi_label=True)
        if (not isinstance(result, dict) or not isinstance(result.get("labels"), list)
                or not isinstance(result.get("scores"), list)
                or len(result["labels"]) != len(LABELS) or len(result["scores"]) != len(LABELS)
                or set(result["labels"]) != set(LABELS.values())):
            raise ValueError("Invalid moderation output")
        output = dict(zip(result["labels"], result["scores"]))
        scores = {}
        for key, label in LABELS.items():
            score = output[label]
            if isinstance(score, bool) or not isinstance(score, (int, float)) or not math.isfinite(score) or not 0 <= score <= 1:
                raise ValueError("Invalid moderation score")
            scores[key] = float(score)
        return {"scores": scores, **metadata()}
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(503, "Community moderation inference is unavailable") from error
    finally:
        _slot.release()
