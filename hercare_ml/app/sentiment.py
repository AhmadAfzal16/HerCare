"""Cached CPU sentiment inference. No clinical distress prediction or raw-text logs."""
from functools import lru_cache
import os
from pathlib import Path
from threading import BoundedSemaphore
import unicodedata

from fastapi import HTTPException
import joblib
from pydantic import BaseModel, ConfigDict, Field


class SentimentRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    text: str = Field(min_length=2, max_length=10000)
    language: str | None = Field(default=None, pattern='^(en|ur|roman_ur)$')


def route_language(text: str) -> str:
    if any('\u0600' <= char <= '\u06ff' for char in text):
        return 'ur'
    roman_words = {'main', 'mein', 'mujhe', 'bohat', 'bahut', 'nahi', 'nahin', 'acha', 'achha',
                   'khush', 'udaas', 'udas', 'pareshan', 'hun', 'hoon', 'hai', 'hain', 'mera', 'meri', 'ka', 'ki'}
    return 'roman_ur' if len(set(text.casefold().split()) & roman_words) >= 2 else 'en'


@lru_cache(maxsize=3)
def load_model(language: str):
    default = Path(__file__).resolve().parents[1] / 'artifacts' / 'sentiment' / 'public_v2'
    root = Path(os.getenv('SENTIMENT_MODEL_DIR', str(default)))
    path = root / f'{language}.joblib'
    if not path.is_file():
        raise HTTPException(503, 'Sentiment model is not provisioned')
    artifact = joblib.load(path)  # Trusted operator-provisioned artifact only.
    if artifact['metadata'].get('task') != 'general_sentiment' or artifact['metadata'].get('language') != language:
        raise HTTPException(503, 'Incompatible sentiment artifact')
    return artifact


_slot = BoundedSemaphore(2)


def analyze(request: SentimentRequest) -> dict:
    language = request.language or route_language(request.text)
    if not _slot.acquire(blocking=False):
        raise HTTPException(503, 'Sentiment inference is busy')
    try:
        artifact = load_model(language)
        text = ' '.join(unicodedata.normalize('NFKC', request.text).casefold().split())
        model = artifact['pipeline']
        probabilities = dict(zip(model.classes_, map(float, model.predict_proba([text])[0])))
        best = max(probabilities, key=probabilities.get)
        vectorizer = artifact['vectorizer']
        candidates = vectorizer.build_analyzer()(text)
        coverage = sum(term in vectorizer.vocabulary_ for term in candidates) / max(len(candidates), 1)
        accepted = coverage >= .2 and probabilities[best] >= artifact['metadata']['abstention_threshold']
        return {'language': language, 'label': best if accepted else None,
                'score': probabilities.get('positive', 0) - probabilities.get('negative', 0),
                'status': 'estimated' if accepted else 'abstained',
                'feature_coverage': coverage,
                'model_version': artifact['metadata']['model_version'], 'validation_status': 'public_benchmark_only',
                'clinical_distress_probability': None, 'clinical_validation': False}
    finally:
        _slot.release()
