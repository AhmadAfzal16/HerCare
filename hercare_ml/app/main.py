from __future__ import annotations

import hmac
import os
import pathlib
from functools import lru_cache
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from .model_runtime import ModelRuntime

app = FastAPI(title="HerCare M4 Risk Service", version="1.0.0", docs_url=None, redoc_url=None)


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
    negative_notification_ratio: float = Field(default=0, ge=0, le=1)
    distress_notification_ratio: float = Field(default=0, ge=0, le=1)
    abuse_notification_ratio: float = Field(default=0, ge=0, le=1)
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
    confidence: float = Field(ge=0, le=1)
    data_completeness: float = Field(ge=0, le=1)
    model_version: str
    model_scope: str
    horizon_days: int | None
    contributors: list[dict[str, Any]]


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
        raise HTTPException(status_code=503, detail="Validated model artifact is unavailable")
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
