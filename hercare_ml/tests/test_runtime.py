import pytest
from pydantic import ValidationError

from app.main import PredictionRequest
from app.model_runtime import ModelRuntime, risk_level


def test_missing_support_is_not_reported_as_a_risk_factor() -> None:
    assert ModelRuntime._contributors({}) == []


def test_zero_support_is_preserved() -> None:
    assert ModelRuntime._contributors({"support_quality": 0}) == [
        {"factor": "limited_support", "strength": 1.0}
    ]


def test_probability_bands_are_stable() -> None:
    assert risk_level(0.24) == "low"
    assert risk_level(0.25) == "moderate"
    assert risk_level(0.50) == "high"
    assert risk_level(0.75) == "severe"


def test_safety_signal_always_escalates() -> None:
    assert risk_level(0.01, safety_positive=True) == "severe"


def test_raw_notification_content_is_rejected() -> None:
    with pytest.raises(ValidationError):
        PredictionRequest.model_validate(
            {"features": {"age": 28, "notification_preview": "private text"}}
        )
