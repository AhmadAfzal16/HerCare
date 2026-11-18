from __future__ import annotations

import hmac
import os
import pathlib
from functools import lru_cache
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response
from starlette.concurrency import run_in_threadpool
from pydantic import BaseModel, ConfigDict, Field

from .model_runtime import ModelRuntime
from .community_moderation import ModerationRequest, moderate, ready as community_ready
from .recovery import RecoveryRequest, summarize
from .sentiment import SentimentRequest, analyze
from .chatbot.schemas import ChatRequest
from .chatbot.engine import compose
from . import voice_transcription

app = FastAPI(title="HerCare Private ML Service", version="1.1.0", docs_url=None, redoc_url=None)


@app.post("/v1/community/moderate")
def moderate_community(request: ModerationRequest, authorization: str | None = Header(default=None),
                       response: Response = None):
    if not os.getenv("ML_SERVICE_TOKEN"):
        raise HTTPException(503, "Private community service token is not configured")
    require_service_token(authorization)
    if response is not None:
        response.headers["Cache-Control"] = "private, no-store"
    return moderate(request)


@app.get("/v1/community/ready")
def ready_community(response: Response, authorization: str | None = Header(default=None)):
    if not os.getenv("ML_SERVICE_TOKEN"):
        raise HTTPException(503, "Private community service token is not configured")
    require_service_token(authorization)
    response.headers["Cache-Control"] = "private, no-store"
    return community_ready()


class FeatureVector(BaseModel):
    model_config = ConfigDict(extra="forbid")
    age: int | None = Field(default=None, ge=15, le=55)
    parity: int | None = Field(default=None, ge=0, le=20)
    education_level: str | None = Field(default=None, max_length=50)
    household_type: str | None = Field(default=None, max_length=10)
    financial_strain: float | None = Field(default=None, ge=0, le=1)
    support_quality: float | None = Field(default=None, ge=0, le=1)
    cesarean: int | None = Field(default=None, ge=0, le=1)
    baby_female: int | None = Field(default=None, ge=0, le=1)
    obstetric_complications: int | None = Field(default=None, ge=0, le=4)
    latest_epds_score: int | None = Field(default=None, ge=0, le=30)
    latest_phq9_score: int | None = Field(default=None, ge=0, le=27)
    safety_positive: bool = False
    average_mood: float | None = Field(default=None, ge=1, le=5)
    mood_slope: float | None = Field(default=None, ge=-4, le=4)
    average_energy: float | None = Field(default=None, ge=1, le=5)
    average_sleep_quality: float | None = Field(default=None, ge=1, le=5)
    average_social_support: float | None = Field(default=None, ge=1, le=5)
    negative_notification_ratio: float | None = Field(default=None, ge=0, le=1)
    distress_notification_ratio: float | None = Field(default=None, ge=0, le=1)
    abuse_notification_ratio: float | None = Field(default=None, ge=0, le=1)
    average_screen_minutes: float | None = Field(default=None, ge=0, le=1440)
    average_social_minutes: float | None = Field(default=None, ge=0, le=1440)
    average_late_night_minutes: float | None = Field(default=None, ge=0, le=480)
    telemetry_days: int = Field(default=0, ge=0, le=14)
    mood_days: int = Field(default=0, ge=0, le=14)


class PredictionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    features: FeatureVector


class PredictionResponse(BaseModel):
    depression_probability: float = Field(ge=0, le=1)
    risk_level: str
    confidence: float | None = Field(ge=0, le=1)
    data_completeness: float = Field(ge=0, le=1)
    model_version: str
    model_scope: str
    horizon_days: int | None
    contributors: list[dict[str, Any]]
    confidence_type: str
    validation_status: str
    feature_contract_version: str
    explanation_type: str


def require_service_token(authorization: str | None = Header(default=None)) -> None:
    expected = os.getenv("ML_SERVICE_TOKEN", "")
    environment = os.getenv("ENVIRONMENT", "development")
    if not expected and environment != "production":
        return
    if not expected:
        raise HTTPException(status_code=503, detail="ML service token is not configured")
    provided = authorization.removeprefix("Bearer ") if authorization else ""
    if not hmac.compare_digest(provided, expected):
        raise HTTPException(status_code=401, detail="Invalid service token")


@lru_cache(maxsize=1)
def runtime() -> ModelRuntime:
    default = pathlib.Path(__file__).parents[1] / "artifacts" / "peri_dep_baseline.joblib"
    path = pathlib.Path(os.getenv("MODEL_PATH", str(default))).resolve()
    if not path.is_file():
        raise HTTPException(status_code=503, detail="Configured research model artifact is unavailable")
    return ModelRuntime(path)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready")
def ready(_: None = Depends(require_service_token)) -> dict[str, Any]:
    model = runtime()
    return {
        "status": "ready",
        "model_version": model.metadata["model_version"],
        "model_scope": model.metadata["model_scope"],
    }


@app.post("/v1/predict", response_model=PredictionResponse)
def predict(
    request: PredictionRequest,
    _: None = Depends(require_service_token),
) -> PredictionResponse:
    result = runtime().predict(request.features.model_dump())
    return PredictionResponse(**result.__dict__)


@app.post('/v1/recovery')
def recovery(request: RecoveryRequest, _: None = Depends(require_service_token)) -> dict:
    try:
        return summarize(request)
    except ValueError as error:
        raise HTTPException(422, 'Invalid or duplicate dated observations') from error


@app.post('/v1/text/sentiment')
def sentiment(request: SentimentRequest, _: None = Depends(require_service_token)) -> dict:
    return analyze(request)


@app.post('/v1/chatbot/reply')
def chatbot(request: ChatRequest, _: None = Depends(require_service_token)) -> dict:
    try:
        return compose(request)
    except (ValueError, OSError):
        raise HTTPException(503, 'Chatbot knowledge/index is unavailable')


@app.post("/v1/audio/transcribe")
async def transcribe_voice(request: Request, _: None = Depends(require_service_token),
                           x_voice_language: str = Header(default="ur")) -> dict:
    content_type = request.headers.get("content-type", "")
    if content_type not in voice_transcription.FORMATS or x_voice_language not in {"en", "ur"}:
        raise HTTPException(422, "Unsupported voice format or language")
    content = bytearray()
    async for chunk in request.stream():
        if len(content) + len(chunk) > voice_transcription.MAX_BYTES:
            raise HTTPException(413, "Voice clip exceeds the upload limit")
        content.extend(chunk)
    return await run_in_threadpool(voice_transcription.transcribe, bytes(content),
                                  content_type, x_voice_language)
