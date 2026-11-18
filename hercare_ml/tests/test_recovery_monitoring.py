from datetime import date, timedelta

import pytest
from pydantic import ValidationError

from app.recovery import RecoveryRequest, summarize
from app.recovery_sleep import clock_summary


def monitor(screenings=None, **kwargs):
    body = {'as_of': '2026-10-09', 'screenings': screenings or [], **kwargs}
    return summarize(RecoveryRequest.model_validate(body))


def assessment(instrument, day, score, **kwargs):
    return {'instrument': instrument, 'version': 'v1', 'language': 'en',
            'completed_date': day, 'score': score, **kwargs}


def test_recorded_screening_directions_are_separate_and_never_future_forecasts():
    result = monitor([assessment('epds', '2026-10-02', 18), assessment('epds', '2026-10-09', 12),
                      assessment('phq9', '2026-09-25', 8), assessment('phq9', '2026-10-09', 14)])
    trends = result['depression_monitoring']['screening_trends']
    assert trends[0]['direction'] == 'lower_recorded_symptoms'
    assert trends[0]['score_change_points'] == -6
    assert trends[1]['direction'] == 'higher_recorded_symptoms'
    assert trends[1]['score_change_points'] == 6
    assert result['depression_monitoring']['future_outlook']['probability'] is None
    assert result['depression_monitoring']['future_outlook']['status'] == 'not_trained'
    assert result['depression_monitoring']['future_outlook']['target'] == 'future_screen_positive'
    assert result['validation_status'] == 'descriptive_not_clinically_validated'


@pytest.mark.parametrize('prior,current,reason', [
    (None, assessment('epds', '2026-10-09', 10), 'baseline_only'),
    (assessment('epds', '2026-10-02', 15, language='ur'), assessment('epds', '2026-10-09', 10), 'language_or_version_changed'),
    (assessment('epds', '2026-10-02', 15, version='v2'), assessment('epds', '2026-10-09', 10), 'language_or_version_changed'),
    (assessment('epds', '2026-09-01', 15), assessment('epds', '2026-10-09', 10), 'outside_followup_window'),
    (assessment('epds', '2026-09-01', 15), assessment('epds', '2026-09-08', 10), 'stale_assessment'),
    (assessment('epds', '2026-10-09', 15), assessment('epds', '2026-10-09', 10), 'baseline_only'),
])
def test_incomparable_or_stale_screenings_do_not_invent_improvement(prior, current, reason):
    result = monitor(([prior] if prior else []) + [current])
    trend = result['depression_monitoring']['screening_trends'][0]
    assert trend['direction'] == 'insufficient_data'
    assert trend['score_change_points'] is None
    assert trend['reason'] == reason
    assert result['screening_changes'] == []


def test_missing_assessments_never_become_negative_or_healthy_defaults():
    result = monitor()
    assert len(result['depression_monitoring']['screening_trends']) == 2
    for trend in result['depression_monitoring']['screening_trends']:
        assert trend['current_score'] is None
        assert trend['reason'] == 'no_completed_assessment'
    assert result['depression_monitoring']['supporting_signals']['sleep']['status'] == 'insufficient_data'


def test_lower_current_total_cannot_hide_prior_safety_history():
    result = monitor([assessment('epds', '2026-10-02', 18, safety_positive=True),
                      assessment('epds', '2026-10-09', 8)])
    assert result['depression_monitoring']['screening_trends'][0]['direction'] == 'lower_recorded_symptoms'
    assert result['requires_safety_review'] is True
    assert all(period['requires_safety_review'] for period in result['periods'])
    assert result['depression_monitoring']['safety_history']['resolution_known'] is False
    assert 'not_present_imminent_danger' in result['depression_monitoring']['safety_history']['meaning']
    # Backend daily de-duplication preserves any earlier same-day positive item.
    result = monitor([assessment('phq9', '2026-10-09', 4, safety_positive_in_day=True)])
    assert result['requires_safety_review'] is True
    assert result['depression_monitoring']['screening_trends'][1]['safety_positive'] is False


def test_display_limit_cannot_hide_safety_positive_history():
    result = monitor([assessment('epds', '2026-10-09', 4)],
                     screening_safety_history={'recorded_positive_count': 130,
                                               'latest_positive_date': '2026-09-01'})
    assert result['requires_safety_review'] is True
    assert result['depression_monitoring']['safety_history']['recorded_positive_count'] == 130
    assert result['depression_monitoring']['screening_trends'][0]['safety_positive'] is False
    with pytest.raises(ValidationError):
        RecoveryRequest.model_validate({'as_of': '2026-10-09',
            'screenings': [assessment('epds', '2026-10-09', 4, safety_positive=True)],
            'screening_safety_history': {'recorded_positive_count': 0, 'latest_positive_date': None}})


def test_sleep_windows_keep_actual_units_and_do_not_assume_longer_is_better():
    rows = []
    for index in range(14):
        rows.append({'entry_date': (date(2026, 9, 26) + timedelta(days=index)).isoformat(),
                     'sleep_minutes': 480.0 if index < 7 else 540.0,
                     'awakenings': 1 if index < 7 else 3,
                     'bedtime_minute': 1430 if index % 2 else 10, 'wake_minute': 420})
    result = monitor(sleep_observations=rows)
    sleep = result['depression_monitoring']['supporting_signals']['sleep']
    weekly = sleep['windows'][1]
    assert sleep['source'] == 'self_reported'
    assert sleep['direction'] == 'descriptive_only'
    assert 'not automatically' in sleep['note']
    assert weekly['sleep_minutes_change'] == 60
    assert weekly['current']['awakenings_mean'] == 3
    assert weekly['current']['quality_mean'] is None
    assert weekly['previous']['coverage'] == 1
    assert sleep['windows'][2]['sleep_minutes_change'] is None
    assert clock_summary([1430, 10])['mean_minute'] == pytest.approx(0)
    assert clock_summary([1430, 10])['variability_minutes'] < 11
    assert clock_summary([0, 720])['mean_minute'] is None


def test_optional_sleep_and_mood_supporting_observations_report_staleness():
    result = monitor(sleep_observations=[{'entry_date': '2026-10-01', 'sleep_minutes': 480.0}],
                     observations=[{'entry_date': '2026-10-01', 'mood_rating': 3}])
    supporting = result['depression_monitoring']['supporting_signals']
    assert supporting['sleep']['stale'] is True
    assert supporting['mood']['stale'] is True
    assert supporting['sleep']['windows'][1]['status'] == 'insufficient_data'


@pytest.mark.parametrize('change', [
    {'observations': [{'entry_date': '2026-10-10', 'mood_rating': 3}]},
    {'observations': [{'entry_date': '2026-10-09', 'mood_rating': '3'}]},
    {'observations': [{'entry_date': '2026-10-09', 'mood_rating': True}]},
    {'screenings': [assessment('phq9', '2026-10-10', 8)]},
    {'screenings': [assessment('phq9', '2026-10-09', 28)]},
    {'screenings': [assessment('phq9', '2026-10-09', 8, safety_positive='false')]},
    {'sleep_observations': [{'entry_date': '2026-10-10', 'sleep_minutes': 480.0}]},
    {'sleep_observations': [{'entry_date': '2026-10-09', 'sleep_minutes': float('nan')}]},
    {'sleep_observations': [{'entry_date': '2026-10-09', 'sleep_minutes': '480'}]},
    {'sleep_observations': [{'entry_date': '2026-10-09', 'sleep_minutes': 480.0, 'bedtime_minute': 1440}]},
    {'sleep_observations': [{'entry_date': '2026-10-09', 'sleep_minutes': 480.0}] * 2},
    {'sleep_observations': [{'entry_date': '2026-10-09', 'sleep_minutes': 480.0, 'raw_journal': 'not accepted'}]},
])
def test_future_duplicate_nonfinite_and_unbounded_observations_are_rejected(change):
    with pytest.raises(ValidationError):
        RecoveryRequest.model_validate({'as_of': '2026-10-09', **change})
