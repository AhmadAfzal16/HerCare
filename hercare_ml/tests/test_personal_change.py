from datetime import date, timedelta

import pytest

from app.personal_change import calculate_personal_change, questionnaire_change


def records(window_days=7, count=None, previous_mood=3, current_mood=3):
    count = window_days if count is None else count
    start = date(2026, 9, 1)
    rows = []
    for period, mood in enumerate((previous_mood, current_mood)):
        for offset in range(count):
            rows.append({"mother_id": "example-mother", "entry_date":
                         (start + timedelta(days=period * window_days + offset)).isoformat(),
                         "mood_rating": mood})
    end = (start + timedelta(days=2 * window_days - 1)).isoformat()
    return rows, end


def evaluate(rows, end, **kwargs):
    return calculate_personal_change("example-mother", rows, as_of=end, **kwargs)


def test_constructed_two_percent_change_preserves_absolute_index_and_coverage():
    rows, end = records(count=5)
    for row in rows:
        row.update(energy_level=3, sleep_quality=3, social_support=3)
    rows[-1]["energy_level"] = 4
    result = evaluate(rows, end)
    assert result["previous"]["index_mean"] == pytest.approx(50)
    assert result["current"]["index_mean"] == pytest.approx(51)
    assert result["relative_index_change_percent"] == pytest.approx(2)
    assert result["index_change_points"] == pytest.approx(1)
    assert result["current"]["coverage"] == pytest.approx(5 / 7)
    assert result["clinical_significance"] == "not_established"


def test_new_optional_information_cannot_create_improvement_by_itself():
    rows, end = records()
    for row in rows[7:]:
        row["social_support"] = 5
    result = evaluate(rows, end)
    assert result["comparable_fields"] == ["mood_rating"]
    assert result["relative_index_change_percent"] == 0


def test_sparse_and_disjoint_observations_are_not_filled_as_normal():
    rows, end = records(count=3)
    result = evaluate(rows, end)
    assert result["direction"] == "insufficient_data"
    assert result["relative_index_change_percent"] is None
    rows, end = records()
    for period in (rows[:7], rows[7:]):
        for index, row in enumerate(period):
            row["energy_level"] = 3 if index < 5 else None
            row["sleep_quality"] = 3 if index >= 2 else None
    result = evaluate(rows, end)
    assert result["direction"] == "insufficient_data"


def test_zero_reference_keeps_absolute_change_and_avoids_division_by_zero():
    rows, end = records(previous_mood=1, current_mood=2)
    result = evaluate(rows, end)
    assert result["index_change_points"] == 25
    assert result["relative_index_change_percent"] is None


def test_worsening_and_mixed_signals_are_visible_and_safety_is_independent():
    rows, end = records(previous_mood=4, current_mood=3)
    result = evaluate(rows, end)
    assert result["relative_index_change_percent"] < 0
    assert result["direction"] == "recorded_index_decreased"
    rows, end = records(previous_mood=3, current_mood=4)
    comparison = questionnaire_change("phq9", "phq9-v1", 8, 14)
    result = evaluate(rows, end, screening_changes=[comparison], safety_positive=True)
    assert result["mixed_signals"] is True
    assert result["requires_safety_review"] is True


def test_slope_uses_calendar_time_with_missing_days():
    rows, end = records()
    offsets = (0, 1, 5, 6)
    rows = [row for index, row in enumerate(rows) if index % 7 in offsets]
    for period in (rows[:4], rows[4:]):
        for index, row in enumerate(period):
            row["mood_rating"] = index + 1
    result = evaluate(rows, end, minimum_coverage=0.5)
    assert result["current"]["index_slope_points_per_day"] == pytest.approx(275 / 26)


@pytest.mark.parametrize("days", [7, 14, 28, 30])
def test_supported_windows_preserve_dates_and_constant_scores(days):
    rows, end = records(window_days=days)
    result = evaluate(rows, end, window_days=days)
    assert result["current"]["expected_days"] == days
    assert result["current"]["end"] == end
    assert result["relative_index_change_percent"] == 0


@pytest.mark.parametrize("mutation", ["other_mother", "duplicate", "future", "invalid_rating"])
def test_bad_or_cross_account_records_are_rejected(mutation):
    rows, end = records()
    if mutation == "other_mother":
        rows[0]["mother_id"] = "other-mother"
    elif mutation == "duplicate":
        rows.append(dict(rows[0]))
    elif mutation == "future":
        rows[0]["entry_date"] = "2027-01-01"
    else:
        rows[0]["mood_rating"] = float("nan")
    with pytest.raises(ValueError):
        evaluate(rows, end)


def test_questionnaire_change_is_separate_from_daily_index():
    result = questionnaire_change("phq9", "phq9-v1", 18, 8)
    assert result["improvement_points"] == 10
    assert result["improvement_percent"] == pytest.approx(100 * 10 / 18)
    assert result["rci"] is None
    assert result["phq9_response_convention_met"] is True
    assert result["phq9_symptom_remission_convention_met"] is False
    assert questionnaire_change("phq9", "phq9-v1", 0, 1)["improvement_percent"] is None


def test_rci_requires_matching_documented_reference_parameters():
    reference = {"instrument": "phq9", "version": "phq9-v1", "baseline_sd": 5,
                 "reliability": 0.8, "source": "synthetic unit-test reference",
                 "population": "synthetic; not clinical validation"}
    result = questionnaire_change("phq9", "phq9-v1", 18, 8, reference)
    assert result["rci"] == pytest.approx(-10 / (5 * (0.4 ** 0.5)))
    assert result["reliable_direction"] == "improved"
    for invalid in ({**reference, "version": "other"}, {**reference, "source": ""},
                    {**reference, "reliability": 1}, {**reference, "baseline_sd": 0}):
        with pytest.raises(ValueError):
            questionnaire_change("phq9", "phq9-v1", 18, 8, invalid)


def test_window_configuration_requires_supported_integer_days():
    rows, end = records()
    for days in (True, 7.0, 8):
        with pytest.raises(ValueError):
            evaluate(rows, end, window_days=days)
