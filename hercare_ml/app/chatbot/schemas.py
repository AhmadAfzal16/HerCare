"""Private model-service inputs: bounded text and allow-listed aggregate context."""
from datetime import date, datetime
from typing import Literal
from zoneinfo import ZoneInfo
from pydantic import BaseModel, ConfigDict, Field, model_validator

Language = Literal['en', 'ur', 'roman_ur']


class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)


class Turn(StrictModel):
    role: Literal['user', 'assistant']
    content: str = Field(min_length=1, max_length=8000)


class Mood(StrictModel):
    window_days: int = Field(default=14, ge=1, le=30)
    record_count: int = Field(ge=0, le=30)
    mean_rating: float | None = Field(default=None, ge=1, le=5)
    latest_date: date | None = None
    trend_per_day: float | None = Field(default=None, ge=-4, le=4)
    coverage_fraction: float = Field(default=0, ge=0, le=1)
    clinical_validation: Literal[False] = False


class Screening(StrictModel):
    instrument: Literal['epds', 'phq9']
    version: str = Field(min_length=1, max_length=40)
    language: Literal['en', 'ur']
    score: int = Field(ge=0, le=30)
    completed_at: datetime
    safety_positive: bool
    age_days: float = Field(default=0, ge=0, le=1000)
    stale: bool = False
    interpretation: Literal['screening_not_diagnosis'] = 'screening_not_diagnosis'

    @model_validator(mode='after')
    def bounded(self):
        if self.instrument == 'phq9' and self.score > 27:
            raise ValueError('PHQ-9 score is at most 27')
        return self


class Risk(StrictModel):
    probability: float = Field(ge=0, le=1)
    risk_level: Literal['low', 'moderate', 'high', 'severe']
    generated_at: datetime
    model_version: str = Field(max_length=120)
    model_scope: str = Field(max_length=80)
    validation_status: Literal['research_only']
    confidence: None = None
    stale: bool = False
    interpretation: Literal['research_estimate_not_diagnosis_or_validated_forecast'] = 'research_estimate_not_diagnosis_or_validated_forecast'


class Sentiment(StrictModel):
    window_days: int = Field(default=14, ge=1, le=30)
    record_count: int = Field(ge=0, le=5000)
    mean_score: float | None = Field(default=None, ge=-1, le=1)
    rule_safety_count: int = Field(ge=0, le=5000)
    clinical_validation: Literal[False] = False
    latest_at: datetime | None = None
    interpretation: Literal['general_sentiment_and_rule_flags_not_clinical_distress_probability'] = 'general_sentiment_and_rule_flags_not_clinical_distress_probability'


class Context(StrictModel):
    personalization_enabled: bool = False
    as_of: datetime | None = None
    mood: Mood | None = None
    screenings: list[Screening] = Field(default_factory=list, max_length=2)
    risk: Risk | None = None
    sentiment: Sentiment | None = None

    @model_validator(mode='after')
    def consent_gate(self):
        if not self.personalization_enabled and any([self.mood, self.screenings, self.risk, self.sentiment]):
            raise ValueError('Aggregate context requires separate personalization consent')
        if self.personalization_enabled and (self.as_of is None or self.as_of.tzinfo is None):
            raise ValueError('Personalization needs an aware as_of timestamp')
        if self.as_of:
            dates = [s.completed_at for s in self.screenings]
            if self.risk:
                dates.append(self.risk.generated_at)
            if self.sentiment and self.sentiment.latest_at:
                dates.append(self.sentiment.latest_at)
            if any(day.tzinfo is None or day > self.as_of for day in dates):
                raise ValueError('Context cannot include naive or future observations')
            if self.mood and self.mood.latest_date and self.mood.latest_date > self.as_of.astimezone(ZoneInfo('Asia/Karachi')).date():
                raise ValueError('Mood date is after the context date')
        return self


class State(StrictModel):
    topic: str | None = Field(default=None, max_length=40)
    cbt_step: int = Field(default=0, ge=0, le=3)


class ChatRequest(StrictModel):
    message: str = Field(min_length=1, max_length=4000)
    language: Language = 'en'
    history: list[Turn] = Field(default_factory=list, max_length=20)
    context: Context = Field(default_factory=Context)
    state: State = Field(default_factory=State)
