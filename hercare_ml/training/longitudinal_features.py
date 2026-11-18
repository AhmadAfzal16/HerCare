"""Generate dated research features from consented HerCare exports, not fake people.

Inputs are a de-identified JSON export: participants, indexes,
daily_observations and assessments (see RESEARCH_EXTRACTION_REPORT.md).
Features use completed local days and only records available at prediction time.
Follow-up measurements go into a separate outcome table; absent labels stay null.
No database connection, raw journal text or fabricated clinical scores are used.
"""

from __future__ import annotations

import argparse
from datetime import date, timedelta
import json
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np
import pandas as pd

WINDOWS = (1, 7, 14, 30)
RANGES = {
    "mood_rating": (1, 5), "energy_level": (1, 5), "sleep_quality": (1, 5),
    "social_support": (1, 5), "sleep_minutes": (0, 1440), "sleep_awakenings": (0, 100),
    "screen_minutes": (0, 1440), "social_minutes": (0, 1440), "late_night_minutes": (0, 1440),
    "therapy_minutes": (0, 1440), "notification_analyzed_count": (0, 100000),
    "notification_negative_count": (0, 100000),
    "recorded_sleep_quality": (1, 5), "bedtime_local_minutes": (0, 1440), "wake_local_minutes": (0, 1440),
}
USAGE = {"screen_minutes", "social_minutes", "late_night_minutes"}
NOTIFICATIONS = {"notification_analyzed_count", "notification_negative_count"}
CLOCKS = {"bedtime_local_minutes", "wake_local_minutes"}
MEASUREMENTS = [name for name in RANGES if not name.startswith("notification_") and name not in CLOCKS]
MAX_SCORES = {"epds": 30, "phq9": 27}
PRIVATE_FIELDS = {"full_name", "name", "email", "phone", "journal_text", "journal_body",
                  "message_body", "transcript", "audio", "raw_notifications", "password"}


def instant(value: str) -> pd.Timestamp:
    result = pd.Timestamp(value)
    if pd.isna(result) or result.tzinfo is None:
        raise ValueError("Timestamps must include timezone offsets")
    return result.tz_convert("UTC")


def day(value: str) -> date:
    result = date.fromisoformat(value)
    if result.isoformat() != value:
        raise ValueError("Dates must use YYYY-MM-DD")
    return result


def number(value, bounds) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not np.isfinite(value):
        raise ValueError("Measurements must be finite numbers or null")
    if not bounds[0] <= value <= bounds[1]:
        raise ValueError("Measurement outside documented bounds")
    return float(value)


def reject_private(value) -> None:
    if isinstance(value, dict):
        if PRIVATE_FIELDS.intersection(value):
            raise ValueError("Research export contains private identity/content fields")
        for child in value.values():
            reject_private(child)
    elif isinstance(value, list):
        for child in value:
            reject_private(child)


def build_features(export: dict, horizon_days: int = 14, tolerance_days: int = 3):
    if export.get("schema_version") != 1 or export.get("data_kind") != "real_consented_observations":
        raise ValueError("Require version 1 real consented export; synthetic data are not accepted")
    if horizon_days < 1 or tolerance_days < 0 or tolerance_days >= horizon_days:
        raise ValueError("Invalid future-outcome window")
    reject_private(export)
    participants, participant_ids = {}, set()
    for profile in export.get("participants", []):
        key = profile["participant_id"]
        if not isinstance(key, str) or not key.strip() or key in participant_ids:
            raise ValueError("Participant IDs must be nonempty, unique pseudonymous strings")
        participant_ids.add(key)
        if profile.get("research_consent") is True:
            participants[key] = ZoneInfo(profile["timezone"])
    daily = {key: [] for key in participants}
    screens = {key: [] for key in participants}
    seen_days = set()
    for entry in export.get("daily_observations", []):
        key = entry["participant_id"]
        if key not in participants:
            continue
        local_day, available = day(entry["date"]), instant(entry["available_at"])
        if (key, local_day) in seen_days:
            raise ValueError("Duplicate participant/day; resolve revisions upstream")
        seen_days.add((key, local_day))
        if local_day > available.tz_convert(participants[key]).date():
            raise ValueError("Observation date is later than its availability time")
        values = {name: number(entry.get(name), bounds) for name, bounds in RANGES.items()}
        if any(values[field] == 1440 for field in CLOCKS):
            raise ValueError("Local clock minutes must be below 1440")
        if entry.get("usage_permission") is not True:
            for name in USAGE:
                values[name] = None
        if entry.get("notification_permission") is not True:
            for name in NOTIFICATIONS:
                values[name] = None
        screen_minutes = values["screen_minutes"]
        for field in ["social_minutes", "late_night_minutes"]:
            if values[field] is not None and screen_minutes is not None and values[field] > screen_minutes:
                raise ValueError("Subset usage minutes exceed total screen minutes")
        analyzed, negative = values["notification_analyzed_count"], values["notification_negative_count"]
        if negative is not None and analyzed is not None and negative > analyzed:
            raise ValueError("Negative notification count exceeds analyzed count")
        daily[key].append({"day": local_day, "available": available, **values})
    screen_keys = set()
    for entry in export.get("assessments", []):
        key = entry["participant_id"]
        if key not in participants:
            continue
        instrument = entry["instrument"]
        if instrument not in MAX_SCORES or not isinstance(entry.get("version"), str) or not entry["version"]:
            raise ValueError("Require supported instrument and exact questionnaire version")
        performed, available = instant(entry["performed_at"]), instant(entry["available_at"])
        if available < performed:
            raise ValueError("Assessment cannot be available before it is performed")
        score = number(entry.get("score"), (0, MAX_SCORES[instrument]))
        if score is None or score % 1:
            raise ValueError("Completed assessments require integer totals; no label imputation")
        signature = (key, instrument, performed)
        if signature in screen_keys:
            raise ValueError("Duplicate assessment timestamp")
        screen_keys.add(signature)
        screens[key].append({"instrument": instrument, "version": entry["version"],
                             "performed": performed, "available": available, "score": score})
    feature_rows, outcome_rows, index_keys = [], [], set()
    ignored_indexes = 0
    for entry in export.get("indexes", []):
        key = entry["participant_id"]
        if key not in participants:
            ignored_indexes += 1
            continue
        index = instant(entry["index_at"])
        if (key, index) in index_keys:
            raise ValueError("Duplicate prediction index")
        index_keys.add((key, index))
        local_index = index.tz_convert(participants[key]).date()
        row = {"participant_id": key, "index_at": index.isoformat()}
        outcome = dict(row)
        history = sorted([r for r in daily[key] if r["available"] <= index and r["day"] < local_index],
                         key=lambda r: r["day"])
        for window in WINDOWS:
            selected = [r for r in history if local_index - timedelta(days=window) <= r["day"]]
            for field in MEASUREMENTS:
                observed = [r for r in selected if r[field] is not None]
                values = np.array([r[field] for r in observed], dtype=float)
                prefix = f"{field}_{window}d"
                row[prefix + "_coverage"] = len(observed) / window
                row[prefix + "_mean"] = float(values.mean()) if len(values) else None
                row[prefix + "_latest_age_days"] = (local_index - observed[-1]["day"]).days if observed else None
                if window > 1:
                    row[prefix + "_sd"] = float(values.std(ddof=1)) if len(values) > 1 else None
                    times = np.array([(r["day"] - local_index).days for r in observed], dtype=float)
                    # OLS slope uses elapsed calendar days, not record position.
                    row[prefix + "_slope_per_day"] = float(np.dot(times - times.mean(), values - values.mean())
                        / np.dot(times - times.mean(), times - times.mean())) if len(values) > 1 else None
            for field in sorted(CLOCKS):
                observed = [r for r in selected if r[field] is not None]
                angles = np.array([r[field] for r in observed], dtype=float) * (2 * np.pi / 1440)
                prefix = f"{field}_{window}d"
                # Clock times wrap at midnight; arithmetic means/slopes are misleading.
                row[prefix + "_sin_mean"] = float(np.sin(angles).mean()) if len(angles) else None
                row[prefix + "_cos_mean"] = float(np.cos(angles).mean()) if len(angles) else None
                row[prefix + "_coverage"] = len(observed) / window
                row[prefix + "_latest_age_days"] = (local_index - observed[-1]["day"]).days if observed else None
            pairs = [r for r in selected if r["notification_analyzed_count"] is not None
                     and r["notification_negative_count"] is not None]
            denominator = sum(r["notification_analyzed_count"] for r in pairs)
            row[f"negative_notification_ratio_{window}d"] = (
                sum(r["notification_negative_count"] for r in pairs) / denominator) if denominator else None
            row[f"notification_pair_coverage_{window}d"] = len(pairs) / window
        for instrument in MAX_SCORES:
            prior = [s for s in screens[key] if s["instrument"] == instrument
                     and s["performed"] <= index and s["available"] <= index]
            baseline = max(prior, key=lambda s: s["performed"], default=None)
            row[f"latest_{instrument}_score"] = baseline["score"] if baseline else None
            row[f"latest_{instrument}_age_days"] = (index - baseline["performed"]).total_seconds() / 86400 if baseline else None
            # Version metadata is retained so cohorts cannot be silently mixed.
            row[f"latest_{instrument}_version"] = baseline["version"] if baseline else None
            row[f"latest_{instrument}_at"] = baseline["performed"].isoformat() if baseline else None
            row[f"latest_{instrument}_available_at"] = baseline["available"].isoformat() if baseline else None
            intended = index + pd.Timedelta(days=horizon_days)
            candidates = [s for s in screens[key] if s["instrument"] == instrument and s["performed"] > index
                          and abs((s["performed"] - intended).total_seconds()) <= tolerance_days * 86400]
            future = min(candidates, key=lambda s: (abs((s["performed"] - intended).total_seconds()), s["performed"]), default=None)
            outcome[f"future_{instrument}_score"] = future["score"] if future else None
            outcome[f"future_{instrument}_at"] = future["performed"].isoformat() if future else None
            outcome[f"future_{instrument}_version"] = future["version"] if future else None
            outcome[f"future_{instrument}_available_at"] = future["available"].isoformat() if future else None
            compatible = future and baseline and future["version"] == baseline["version"]
            outcome[f"{instrument}_change_points"] = future["score"] - baseline["score"] if compatible else None
        feature_rows.append(row)
        outcome_rows.append(outcome)
    features, outcomes = pd.DataFrame(feature_rows), pd.DataFrame(outcome_rows)
    audit = {"schema_version": 1, "data_kind": "real_consented_observations", "clinical_promotion_allowed": False,
             "indexes": len(features), "consented_participants": len(participants),
             "indexes_excluded_without_consent": ignored_indexes, "windows_days": list(WINDOWS),
             "horizon_days": horizon_days, "tolerance_days": tolerance_days,
             "predictor_columns": [c for c in features if c not in {"participant_id", "index_at"}],
             "split_group": "participant_id", "imputation_performed": False,
             "limitations": ["Coverage is not evidence of wellness; missing follow-up is not recovery.",
                             "Use participant-group and temporal validation; overlapping windows are not independent people.",
                             "Activity duration measures interaction, not therapeutic benefit or causal treatment effect.",
                             "No unvalidated weighting formula, study odds ratio or generated score becomes clinical truth."]}
    return features, outcomes, audit


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.output_dir.exists():
        raise FileExistsError("Choose a new output directory")
    with args.input.open(encoding="utf-8") as stream:
        features, outcomes, audit = build_features(json.load(stream))
    if features.empty:
        raise ValueError("No consented prediction indexes; no training dataset generated")
    args.output_dir.mkdir(parents=True, exist_ok=False)
    features.to_csv(args.output_dir / "features.csv", index=False)
    outcomes.to_csv(args.output_dir / "outcomes.csv", index=False)
    with (args.output_dir / "audit.json").open("x", encoding="utf-8") as stream:
        json.dump(audit, stream, indent=2, allow_nan=False)
    print(f"Extracted {len(features)} real participant/index rows; no model deployed")


if __name__ == "__main__":
    main()
