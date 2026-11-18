"""Experimental descriptive change in one mother's recorded wellbeing.

This descriptive calculation is separate from prediction and clinical alerts.
Daily ratings, questionnaire change, and measurement reliability retain their
own units. No trained forecasts or population odds ratios enter this index.
"""

from __future__ import annotations

import math
from datetime import date, timedelta
from statistics import mean, stdev
from typing import Any

VERSION = "personal-change-research-v0"
WEIGHTS = {"mood_rating": 0.4, "energy_level": 0.2,
           "sleep_quality": 0.2, "social_support": 0.2}


def _number(value: Any, low: float, high: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("Expected a numeric observation.")
    if not math.isfinite(value) or not low <= value <= high:
        raise ValueError("Observation is outside its permitted range.")
    return float(value)


def _day(value: Any) -> date:
    if not isinstance(value, str):
        raise ValueError("Observation dates must use YYYY-MM-DD.")
    parsed = date.fromisoformat(value)
    if parsed.isoformat() != value:
        raise ValueError("Observation dates must use YYYY-MM-DD.")
    return parsed


def _window(rows: list[dict], fields: list[str], start: date, end: date,
            window_days: int) -> dict:
    complete = [row for row in rows if all(row.get(field) is not None for field in fields)]
    total_weight = sum(WEIGHTS[field] for field in fields)
    scores = [100 * (sum(WEIGHTS[field] * row[field] for field in fields)
                     / total_weight - 1) / 4 for row in complete]
    slope = None
    if len(scores) >= 2:
        times = [(row["day"] - start).days for row in complete]
        time_mean, score_mean = mean(times), mean(scores)
        denominator = sum((time - time_mean) ** 2 for time in times)
        slope = sum((time - time_mean) * (score - score_mean)
                    for time, score in zip(times, scores)) / denominator
    return {"start": start.isoformat(), "end": end.isoformat(),
            "observed_days": len(complete), "expected_days": window_days,
            "coverage": len(complete) / window_days,
            "index_mean": mean(scores) if scores else None,
            "index_sd": stdev(scores) if len(scores) >= 2 else None,
            "index_slope_points_per_day": slope}


def questionnaire_change(instrument: str, version: str,
                         previous_score: int, current_score: int,
                         reference: dict | None = None) -> dict:
    """Same-instrument/version change; reliability reference is optional.

    The caller must select actual completed, dated assessments of the same
    instrument/version. This helper never treats missing scores as zero.
    """
    maximum = {"epds": 30, "phq9": 27}.get(instrument)
    if maximum is None or not version:
        raise ValueError("A supported questionnaire and version are required.")
    if any(isinstance(score, bool) or not isinstance(score, int)
           for score in (previous_score, current_score)):
        raise ValueError("Questionnaire totals must be integers.")
    old = _number(previous_score, 0, maximum)
    new = _number(current_score, 0, maximum)
    delta = old - new
    percent = 100 * delta / old if old > 0 else None
    rci = None
    if reference is not None:
        if reference.get("instrument") != instrument or reference.get("version") != version:
            raise ValueError("Reliability reference must match the questionnaire version.")
        if not reference.get("source") or not reference.get("population"):
            raise ValueError("Reliability source and population must be documented.")
        sd = _number(reference.get("baseline_sd"), 0, math.inf)
        reliability = _number(reference.get("reliability"), 0, 1)
        if sd == 0 or reliability == 1:
            raise ValueError("Reliable change requires positive SD and reliability below one.")
        rci = (new - old) / (sd * math.sqrt(2 * (1 - reliability)))
    return {"instrument": instrument, "version": version,
            "previous_score": previous_score, "current_score": current_score,
            "score_change_points": current_score - previous_score,
            "recorded_score_direction": "lower_recorded_symptoms" if delta > 0 else
            "higher_recorded_symptoms" if delta < 0 else "no_change",
            "interpretation": "same_instrument_recorded_symptom_change_not_diagnosis",
            "improvement_points": delta, "improvement_percent": percent,
            "rci": rci,
            "reliable_direction": None if rci is None else
            ("improved" if rci < -1.96 else "worsened" if rci > 1.96 else "not_established"),
            "phq9_response_convention_met": None if instrument != "phq9" or old < 10
            else percent >= 50,
            "phq9_symptom_remission_convention_met": None if instrument != "phq9" or old < 10
            else new < 5}


def calculate_personal_change(mother_id: str, observations: list[dict],
                              *, as_of: str, window_days: int = 7,
                              minimum_coverage: float = 0.7,
                              screening_changes: list[dict] | None = None,
                              safety_positive: bool = False) -> dict:
    """Compare adjacent local-date windows with the same observed components.

    Coverage is an experimental data-quality rule, not a clinical cutoff.
    Screening comparisons are calculated separately by questionnaire_change.
    """
    if not isinstance(mother_id, str) or not mother_id.strip():
        raise ValueError("One mother ID is required.")
    if isinstance(window_days, bool) or not isinstance(window_days, int) or window_days not in (1, 7, 14, 28, 30):
        raise ValueError("Use a 1, 7, 14, 28 or 30 day comparison window.")
    coverage_limit = _number(minimum_coverage, 0.5, 1)
    if not isinstance(safety_positive, bool):
        raise ValueError("Safety state must be explicit.")
    current_end = _day(as_of)
    current_start = current_end - timedelta(days=window_days - 1)
    previous_end = current_start - timedelta(days=1)
    previous_start = previous_end - timedelta(days=window_days - 1)
    rows, seen = [], set()
    for observation in observations:
        if observation.get("mother_id") != mother_id:
            raise ValueError("A comparison cannot mix mother accounts.")
        day = _day(observation.get("entry_date"))
        if day > current_end:
            raise ValueError("Future observations cannot enter a past comparison.")
        if day in seen:
            raise ValueError("Resolve duplicate check-ins before calculating change.")
        seen.add(day)
        row = {"day": day}
        for field in WEIGHTS:
            value = observation.get(field)
            row[field] = None if value is None else _number(value, 1, 5)
        if row["mood_rating"] is None:
            raise ValueError("Each check-in needs its observed mood rating.")
        if previous_start <= day <= current_end:
            rows.append(row)
    rows.sort(key=lambda row: row["day"])
    previous_rows = [row for row in rows if row["day"] <= previous_end]
    current_rows = [row for row in rows if row["day"] >= current_start]
    fields = [field for field in WEIGHTS if all(
        sum(row[field] is not None for row in period) / window_days >= coverage_limit
        for period in (previous_rows, current_rows))]
    # Mood is mandatory; sparse optional observations never become healthy defaults.
    if "mood_rating" not in fields:
        fields = ["mood_rating"]
    previous = _window(previous_rows, fields, previous_start, previous_end, window_days)
    current = _window(current_rows, fields, current_start, current_end, window_days)
    eligible = all(period["coverage"] >= coverage_limit for period in (previous, current))
    change = current["index_mean"] - previous["index_mean"] if eligible else None
    percent = (100 * change / previous["index_mean"]
               if eligible and previous["index_mean"] > 0 else None)
    direction = ("insufficient_data" if change is None else "unchanged" if abs(change) < 1e-9
                 else "recorded_index_increased" if change > 0 else "recorded_index_decreased")
    comparisons = screening_changes or []
    mixed = False
    for comparison in comparisons:
        delta = _number(comparison.get("improvement_points"), -30, 30)
        if change is not None and change * delta < 0:
            mixed = True
    return {"calculation_version": VERSION, "validation_status": "experimental",
            "mother_id": mother_id, "comparable_fields": fields,
            "normalised_weights": {field: WEIGHTS[field] / sum(WEIGHTS[f] for f in fields)
                                   for field in fields},
            "previous": previous, "current": current,
            "index_change_points": change, "relative_index_change_percent": percent,
            "direction": direction, "mixed_signals": mixed,
            "screening_changes": comparisons,
            "requires_safety_review": safety_positive,
            "clinical_significance": "not_established",
            "measurement_uncertainty": "not_estimated"}
