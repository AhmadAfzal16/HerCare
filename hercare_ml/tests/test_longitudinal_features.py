from copy import deepcopy

import pandas as pd
import pytest

from training.longitudinal_features import build_features


def exported():
    return {
        "schema_version": 1, "data_kind": "real_consented_observations",
        "participants": [{"participant_id": "p1", "research_consent": True, "timezone": "Asia/Karachi"}],
        "indexes": [{"participant_id": "p1", "index_at": "2026-10-08T00:00:00+05:00"}],
        "daily_observations": [
            {"participant_id": "p1", "date": "2026-10-03", "available_at": "2026-10-03T22:00:00+05:00", "mood_rating": 1},
            {"participant_id": "p1", "date": "2026-10-07", "available_at": "2026-10-07T22:00:00+05:00", "mood_rating": 5},
        ],
        "assessments": [
            {"participant_id": "p1", "instrument": "phq9", "version": "v1", "score": 16,
             "performed_at": "2026-10-01T12:00:00+05:00", "available_at": "2026-10-01T12:00:00+05:00"},
            {"participant_id": "p1", "instrument": "phq9", "version": "v1", "score": 14,
             "performed_at": "2026-10-22T12:00:00+05:00", "available_at": "2026-10-22T12:00:00+05:00"},
        ],
    }


def test_calendar_slopes_and_actual_observation_coverage():
    features, outcomes, audit = build_features(exported())
    row = features.iloc[0]
    assert row["mood_rating_7d_mean"] == 3
    assert row["mood_rating_7d_slope_per_day"] == 1  # 4 points / 4 days, not / 1 record
    assert row["mood_rating_7d_coverage"] == 2 / 7
    assert row["mood_rating_1d_mean"] == 5
    assert pd.isna(row["sleep_minutes_7d_mean"])
    assert row["sleep_minutes_7d_coverage"] == 0
    assert row["latest_phq9_score"] == 16
    assert outcomes.iloc[0]["future_phq9_score"] == 14
    assert outcomes.iloc[0]["phq9_change_points"] == -2
    assert "future_phq9_score" not in features
    assert audit["split_group"] == "participant_id"


def test_future_and_late_arriving_history_do_not_leak_into_features():
    value = exported()
    value["daily_observations"] += [
        {"participant_id": "p1", "date": "2026-10-06", "available_at": "2026-10-09T01:00:00+05:00", "mood_rating": 1},
        {"participant_id": "p1", "date": "2026-10-08", "available_at": "2026-10-08T23:00:00+05:00", "mood_rating": 1},
    ]
    value["assessments"][0]["available_at"] = "2026-10-09T01:00:00+05:00"
    features, _, _ = build_features(value)
    assert features.iloc[0]["mood_rating_7d_mean"] == 3
    assert features.iloc[0]["latest_phq9_score"] is None


def test_permissions_and_zero_notification_denominators_stay_missing():
    value = exported()
    value["daily_observations"][0].update({"screen_minutes": 0, "notification_analyzed_count": 0,
                                          "notification_negative_count": 0, "usage_permission": False,
                                          "notification_permission": False})
    features, _, _ = build_features(value)
    assert features.iloc[0]["screen_minutes_7d_mean"] is None
    assert features.iloc[0]["negative_notification_ratio_7d"] is None
    value["daily_observations"][0]["usage_permission"] = True
    value["daily_observations"][0]["notification_permission"] = True
    features, _, _ = build_features(value)
    assert features.iloc[0]["screen_minutes_7d_mean"] == 0
    assert features.iloc[0]["negative_notification_ratio_7d"] is None


def test_notification_ratio_uses_matched_counts_and_not_average_daily_ratios():
    value = exported()
    value["daily_observations"][0].update({"notification_permission": True, "notification_analyzed_count": 10,
                                          "notification_negative_count": 1})
    value["daily_observations"][1].update({"notification_permission": True, "notification_analyzed_count": 1,
                                          "notification_negative_count": 1})
    features, _, _ = build_features(value)
    assert features.iloc[0]["negative_notification_ratio_7d"] == 2 / 11


def test_no_research_consent_no_extraction():
    value = exported()
    value["participants"][0]["research_consent"] = False
    features, outcomes, audit = build_features(value)
    assert features.empty and outcomes.empty
    assert audit["indexes_excluded_without_consent"] == 1


def test_notification_and_usage_permissions_are_independent():
    value = exported()
    value["daily_observations"][0].update({"usage_permission": False, "notification_permission": True,
                                          "screen_minutes": 90, "notification_analyzed_count": 10,
                                          "notification_negative_count": 2})
    features, _, _ = build_features(value)
    assert features.iloc[0]["screen_minutes_7d_mean"] is None
    assert features.iloc[0]["negative_notification_ratio_7d"] == .2


def test_missing_followup_and_different_versions_do_not_create_recovery_truth():
    value = exported()
    value["assessments"][1]["version"] = "different"
    _, outcomes, _ = build_features(value)
    assert outcomes.iloc[0]["phq9_change_points"] is None
    assert outcomes.iloc[0]["future_epds_score"] is None
    value["assessments"].pop()
    _, outcomes, _ = build_features(value)
    assert outcomes.iloc[0]["future_phq9_score"] is None


@pytest.mark.parametrize("mutation, message", [
    (lambda e: e.update(data_kind="synthetic"), "synthetic"),
    (lambda e: e["participants"][0].update(full_name="Private"), "private"),
    (lambda e: e["indexes"][0].update(index_at="2026-10-08T00:00:00"), "timezone"),
    (lambda e: e["daily_observations"][0].update(mood_rating=6), "bounds"),
    (lambda e: e["daily_observations"].append(deepcopy(e["daily_observations"][0])), "Duplicate participant/day"),
    (lambda e: e["indexes"].append(deepcopy(e["indexes"][0])), "Duplicate prediction"),
    (lambda e: e["assessments"][0].update(score=None), "integer totals"),
    (lambda e: e["assessments"][0].update(available_at="2026-09-30T12:00:00Z"), "before"),
])
def test_invalid_or_private_export_fails_closed(mutation, message):
    value = exported()
    mutation(value)
    with pytest.raises(ValueError, match=message):
        build_features(value)
