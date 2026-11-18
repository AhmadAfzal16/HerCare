"""Observed monitoring, kept separate from untrained future prediction."""
from datetime import date, timedelta
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt, model_validator
from .personal_change import calculate_personal_change, questionnaire_change
from .recovery_sleep import SleepObservation, supporting_signals


class Observation(BaseModel):
    model_config = ConfigDict(extra='forbid')
    entry_date: date
    mood_rating: StrictInt = Field(ge=1, le=5)
    energy_level: StrictInt | None = Field(default=None, ge=1, le=5)
    sleep_quality: StrictInt | None = Field(default=None, ge=1, le=5)
    social_support: StrictInt | None = Field(default=None, ge=1, le=5)


class Screening(BaseModel):
    model_config = ConfigDict(extra='forbid')
    instrument: Literal['epds', 'phq9']
    version: str = Field(min_length=1, max_length=40)
    language: Literal['en', 'ur']
    completed_date: date
    score: StrictInt = Field(ge=0, le=30)
    safety_positive: StrictBool = False
    safety_positive_in_day: StrictBool = False

    @model_validator(mode='after')
    def valid_score(self):
        if self.instrument == 'phq9' and self.score > 27:
            raise ValueError('PHQ-9 maximum is 27')
        return self


class ScreeningSafetyHistory(BaseModel):
    """Aggregate of completed safety-positive assessments before display limits."""
    model_config = ConfigDict(extra='forbid')
    recorded_positive_count: StrictInt = Field(ge=0, le=1000000)
    latest_positive_date: date | None = None

    @model_validator(mode='after')
    def consistent_history(self):
        if (self.recorded_positive_count > 0) != (self.latest_positive_date is not None):
            raise ValueError('Safety history count and latest date must agree')
        return self


class RecoveryRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    as_of: date
    observations: list[Observation] = Field(default_factory=list, max_length=60)
    screenings: list[Screening] = Field(default_factory=list, max_length=120)
    sleep_observations: list[SleepObservation] = Field(default_factory=list, max_length=60)
    screening_safety_history: ScreeningSafetyHistory | None = None

    @model_validator(mode='after')
    def dated_observations(self):
        for rows in (self.observations, self.sleep_observations):
            days = [row.entry_date for row in rows]
            if len(set(days)) != len(days):
                raise ValueError('Resolve duplicate daily observations before monitoring')
            if any(day > self.as_of for day in days):
                raise ValueError('Future observations cannot enter observed monitoring')
        if any(row.completed_date > self.as_of for row in self.screenings):
            raise ValueError('Future screening results cannot enter observed monitoring')
        if self.screening_safety_history:
            history = self.screening_safety_history
            if history.latest_positive_date and history.latest_positive_date > self.as_of:
                raise ValueError('Future safety history cannot enter observed monitoring')
            recorded = [s for s in self.screenings if s.safety_positive or s.safety_positive_in_day]
            if len(recorded) > history.recorded_positive_count or any(
                    s.completed_date > history.latest_positive_date for s in recorded):
                raise ValueError('Completed safety records and aggregate history disagree')
        return self


def screening_trend(instrument: str, cadence: int, screenings: list[Screening], as_of: date) -> tuple[dict, dict | None]:
    eligible = [s for s in screenings if s.instrument == instrument]
    current = eligible[-1] if eligible else None
    trend = {'instrument': instrument, 'version': current.version if current else None,
             'language': current.language if current else None,
             'current_score': current.score if current else None, 'previous_score': None,
             'current_date': current.completed_date.isoformat() if current else None,
             'previous_date': None, 'score_change_points': None, 'actual_interval_days': None,
             'direction': 'insufficient_data', 'stale': False,
             'age_days': (as_of - current.completed_date).days if current else None,
             'safety_positive': current.safety_positive if current else False,
             'reason': 'no_completed_assessment',
             'comparison_rule': {'scheduled_interval_days': cadence, 'tolerance_days': 3,
                                 'meaning': 'project_comparability_rule_not_clinical_validation'}}
    if current is None:
        return trend, None
    trend['stale'] = trend['age_days'] > cadence
    prior = [s for s in eligible[:-1] if s.completed_date < current.completed_date]
    matching = [s for s in prior if s.version == current.version and s.language == current.language]
    if not matching:
        trend['reason'] = 'language_or_version_changed' if prior else 'baseline_only'
        if trend['stale']:
            trend['reason'] = 'stale_assessment'
        return trend, None
    intended = current.completed_date - timedelta(days=cadence)
    previous = min(matching, key=lambda s: (abs((s.completed_date - intended).days), -s.completed_date.toordinal()))
    interval = (current.completed_date - previous.completed_date).days
    trend.update(previous_score=previous.score, previous_date=previous.completed_date.isoformat(), actual_interval_days=interval)
    if trend['stale'] or abs(interval - cadence) > 3:
        trend['reason'] = 'stale_assessment' if trend['stale'] else 'outside_followup_window'
        return trend, None
    result = questionnaire_change(instrument, current.version, previous.score, current.score)
    result.update(language=current.language, previous_date=previous.completed_date.isoformat(),
                  current_date=current.completed_date.isoformat(), actual_interval_days=interval)
    trend.update(score_change_points=result['score_change_points'], direction=result['recorded_score_direction'], reason='comparable_assessments')
    return trend, result


def summarize(request: RecoveryRequest) -> dict:
    observations = [{'mother_id': 'self', **row.model_dump(mode='json')} for row in request.observations]
    screenings = sorted(request.screenings, key=lambda s: s.completed_date)
    comparisons, trends = [], []
    for instrument, cadence in [('epds', 7), ('phq9', 14)]:
        trend, result = screening_trend(instrument, cadence, screenings, request.as_of)
        trends.append(trend)
        if result is not None:
            comparisons.append(result)
    # A lower later total is not proof that earlier safety concerns resolved.
    # No resolution field is available; review is not an imminent-danger claim.
    safety_records = [s for s in screenings if s.safety_positive or s.safety_positive_in_day]
    history = request.screening_safety_history
    positive_count = history.recorded_positive_count if history else len(safety_records)
    safety = positive_count > 0
    periods = []
    for window in [1, 7, 14, 30]:
        result = calculate_personal_change('self', observations, as_of=request.as_of.isoformat(),
                    window_days=window, screening_changes=comparisons, safety_positive=safety)
        result.pop('mother_id')
        periods.append({'window_days': window, **result})
    positive_date = history.latest_positive_date if history else max((s.completed_date for s in safety_records), default=None)
    monitoring = {'status': 'observed_monitoring_only', 'requires_safety_review': safety,
                  'screening_trends': trends, 'supporting_signals': supporting_signals(request, periods),
                  'future_outlook': {'status': 'not_trained', 'probability': None, 'horizon_days': 14,
                                     'target': 'future_screen_positive',
                                     'reason': 'genuine_dated_followup_model_unavailable',
                                     'notice': 'Future risk needs genuine dated follow-up outcomes and independent validation. The current baseline is not a future-depression forecast.'},
                  'safety_history': {'recorded_positive_count': positive_count,
                                     'latest_positive_date': positive_date.isoformat() if positive_date else None,
                                     'resolution_known': False if safety else None,
                                     'meaning': 'recorded_safety_history_for_review_not_present_imminent_danger_assessment'},
                  'interpretation': 'EPDS and PHQ-9 remain separate recorded symptom trends, not diagnosis, remission or proven recovery.'}
    return {'as_of': request.as_of.isoformat(), 'periods': periods, 'screening_changes': comparisons,
            'requires_safety_review': safety, 'validation_status': 'descriptive_not_clinically_validated',
            'depression_monitoring': monitoring,
            'notice': 'Change in recorded wellbeing or screening scores is not a diagnosis or proof that treatment worked.'}
