"""Optional, self-hosted multilingual triage. Human publication approval is required."""
from functools import lru_cache
import os
from threading import BoundedSemaphore

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field


class ModerationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(min_length=2, max_length=2200)


LABELS = {
    "self_harm": "self-harm or suicide",
    "bullying": "bullying, abuse or harassment",
    "spam": "spam or advertising",
    "medical_advice": "instructions about medication or medical treatment",
    "support": "kind peer support and personal recovery experiences",
}
_slot = BoundedSemaphore(1)


@lru_cache(maxsize=1)
def classifier():
    model_path = os.getenv("COMMUNITY_MODEL_PATH")
    if not model_path:
        raise HTTPException(503, "Community moderation model is not configured")
    try:
        from transformers import AutoModelForSequenceClassification, AutoTokenizer, pipeline
        tokenizer = AutoTokenizer.from_pretrained(model_path, local_files_only=True, trust_remote_code=False)
        model = AutoModelForSequenceClassification.from_pretrained(
            model_path, local_files_only=True, trust_remote_code=False, use_safetensors=True,
        )
        return pipeline("zero-shot-classification", model=model, tokenizer=tokenizer, device=-1)
    except Exception as error:
        raise HTTPException(503, "Community moderation model is unavailable") from error


def moderate(request: ModerationRequest):
    if not _slot.acquire(blocking=False):
        raise HTTPException(503, "Community moderation is busy")
    try:
        model = classifier()
        scores = {key: 0.0 for key in LABELS}
        # Overlap catches signals spanning chunks; don't silently truncate long posts.
        for offset in range(0, len(request.text), 360):
            result = model(request.text[offset:offset + 440], candidate_labels=list(LABELS.values()), multi_label=True)
            output = dict(zip(result["labels"], result["scores"]))
            for key, label in LABELS.items():
                scores[key] = max(scores[key], float(output[label]))
        return {"scores": scores, "model_version": os.getenv("COMMUNITY_MODEL_VERSION", "mdeberta-xnli-triage-v1")}
    finally:
        _slot.release()
