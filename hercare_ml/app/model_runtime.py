from __future__ import annotations

import math
import pathlib
from dataclasses import dataclass
from typing import Any

import joblib
import pandas as pd


@dataclass(frozen=True)
class Prediction:
    depression_probability: float
    risk_level: str
    confidence: float
    data_completeness: float
    model_version: str
    model_scope: str
    horizon_days: int | None
    contributors: list[dict[str, Any]]


def risk_level(probability: float, safety_positive: bool = False) -> str:
    if safety_positive:
        return "severe"
    if probability < 0.25:
        return "low"
    if probability < 0.50:
        return "moderate"
    if probability < 0.75:
        return "high"
    return "severe"


class ModelRuntime:
    def __init__(self, artifact_path: pathlib.Path):
        artifact = joblib.load(artifact_path)
        self.pipeline = artifact["pipeline"]
        self.metadata = artifact["metadata"]
        self.feature_names: list[str] = self.metadata["feature_names"]

    def predict(self, features: dict[str, Any]) -> Prediction:
        values = {name: features.get(name) for name in self.feature_names}
        present = sum(
            value is not None and not (isinstance(value, float) and math.isnan(value))
            for value in values.values()
        )
        completeness = present / len(self.feature_names)
        probability = float(self.pipeline.predict_proba(pd.DataFrame([values]))[0, 1])
        confidence = min(0.99, 0.5 + abs(probability - 0.5)) * completeness
        contributors = self._contributors(features)
        return Prediction(
            depression_probability=probability,
            risk_level=risk_level(probability, bool(features.get("safety_positive"))),
            confidence=confidence,
            data_completeness=completeness,
            model_version=self.metadata["model_version"],
            model_scope=self.metadata["model_scope"],
            horizon_days=self.metadata.get("horizon_days"),
            contributors=contributors,
        )

    @staticmethod
    def _contributors(features: dict[str, Any]) -> list[dict[str, Any]]:
        candidates = [
            ("recent_screening", float(features.get("latest_epds_score") or 0) / 30),
            ("low_mood", max(0.0, (3 - float(features.get("average_mood") or 3)) / 2)),
            ("distress_signals", float(features.get("distress_notification_ratio") or 0)),
            ("late_night_use", min(1.0, float(features.get("average_late_night_minutes") or 0) / 180)),
            ("limited_support", max(0.0, 1 - float(features.get("support_quality") or 0.5))),
        ]
        return [
            {"factor": name, "strength": round(strength, 3)}
            for name, strength in sorted(candidates, key=lambda item: item[1], reverse=True)
            if strength > 0
        ][:3]

