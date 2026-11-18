"""Supporting self-reported sleep, never a depression or recovery classifier."""
import math
from datetime import date, timedelta
from statistics import mean

from pydantic import BaseModel, ConfigDict, Field, StrictInt


class SleepObservation(BaseModel):
    model_config = ConfigDict(extra='forbid')
    entry_date: date
    sleep_minutes: float = Field(gt=0, le=1440, allow_inf_nan=False, strict=True)
    awake_minutes: StrictInt | None = Field(default=None, ge=0, le=1439)
    awakenings: StrictInt | None = Field(default=None, ge=0, le=50)
    quality: StrictInt | None = Field(default=None, ge=1, le=5)
    bedtime_minute: StrictInt | None = Field(default=None, ge=0, le=1439)
    wake_minute: StrictInt | None = Field(default=None, ge=0, le=1439)


def clock_summary(values: list[int]) -> dict:
    """23:55 and 00:05 are adjacent times, not twelve hours apart."""
    if not values:
        return {'mean_minute': None, 'variability_minutes': None}
    scale = 2 * math.pi / 1440
    sine = mean(math.sin(value * scale) for value in values)
    cosine = mean(math.cos(value * scale) for value in values)
    resultant = min(1.0, math.hypot(sine, cosine))
    if resultant < 1e-12:
        return {'mean_minute': None, 'variability_minutes': None}
    clock_mean = (math.atan2(sine, cosine) / scale) % 1440
    if math.isclose(clock_mean, 1440, abs_tol=1e-9):
        clock_mean = 0.0
    variability = math.sqrt(max(0, -2 * math.log(resultant))) / scale if len(values) >= 2 else None
    return {'mean_minute': clock_mean, 'variability_minutes': variability}


def sleep_window(rows: list[SleepObservation], start: date, end: date, window: int) -> dict:
    selected = [row for row in rows if start <= row.entry_date <= end]
    result = {'start': start.isoformat(), 'end': end.isoformat(), 'observed_days': len(selected),
              'expected_days': window, 'coverage': len(selected) / window}
    for field in ('sleep_minutes', 'awake_minutes', 'awakenings', 'quality'):
        values = [getattr(row, field) for row in selected if getattr(row, field) is not None]
        result[f'{field}_mean'] = mean(values) if values else None
        result[f'{field}_observed_days'] = len(values)
    for field in ('bedtime_minute', 'wake_minute'):
        values = [getattr(row, field) for row in selected if getattr(row, field) is not None]
        result[field] = {**clock_summary(values), 'observed_days': len(values)}
    return result


def supporting_signals(request, periods: list[dict]) -> dict:
    latest_mood = max((row.entry_date for row in request.observations), default=None)
    latest_sleep = max((row.entry_date for row in request.sleep_observations), default=None)
    sleep_windows = []
    for window in (1, 7, 14, 30):
        start = request.as_of - timedelta(days=window - 1)
        previous_end = start - timedelta(days=1)
        previous_start = previous_end - timedelta(days=window - 1)
        previous = sleep_window(request.sleep_observations, previous_start, previous_end, window)
        current = sleep_window(request.sleep_observations, start, request.as_of, window)
        comparable = all(part['coverage'] >= 0.7 for part in (previous, current))
        change = current['sleep_minutes_mean'] - previous['sleep_minutes_mean'] if comparable else None
        sleep_windows.append({'window_days': window, 'status': 'comparable_observations' if comparable else 'insufficient_data',
                              'previous': previous, 'current': current, 'sleep_minutes_change': change})
    def age(day):
        return (request.as_of - day).days if day else None
    return {'mood': {'status': 'observations_available' if latest_mood else 'insufficient_data',
                     'direction': 'descriptive_only', 'latest_date': latest_mood.isoformat() if latest_mood else None,
                     'age_days': age(latest_mood), 'stale': age(latest_mood) > 2 if latest_mood else False,
                     'note': 'Experimental recorded wellbeing index, not a depression or treatment-effect measure.',
                     'windows': periods},
            'sleep': {'status': 'observations_available' if latest_sleep else 'insufficient_data',
                      'direction': 'descriptive_only', 'source': 'self_reported',
                      'latest_date': latest_sleep.isoformat() if latest_sleep else None,
                      'age_days': age(latest_sleep), 'stale': age(latest_sleep) > 2 if latest_sleep else False,
                      'note': 'Duration, interruptions and local clock timing are separate supporting observations. More sleep does not automatically mean mental health improved.',
                      'windows': sleep_windows}}
