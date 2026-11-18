import json

import joblib
import numpy as np
import pandas as pd
import pytest

from app.model_runtime import ModelRuntime
from training.forecast_cohort import ForecastSpec, prepare
from training.synthetic_m4 import (
    DATA_KIND,
    KEYS,
    WINDOWS_PER_MOTHER,
    _direction,
    experiment,
    generate,
    split_participants,
)


def test_reproducible_dated_data_and_participant_holdouts():
    features, outcomes = generate(23, 30)
    same_features, same_outcomes = generate(23, 30)
    pd.testing.assert_frame_equal(features, same_features)
    pd.testing.assert_frame_equal(outcomes, same_outcomes)

    assert set(features.data_kind) == {DATA_KIND}
    assert set(outcomes.data_kind) == {DATA_KIND}
    assert {'future_epds', 'followup_day'}.isdisjoint(features.columns)
    lags = pd.to_datetime(outcomes.followup_day) - pd.to_datetime(outcomes.index_day)
    assert lags.dt.days.between(11, 17).all()
    joined = features.merge(outcomes, on=KEYS, validate='one_to_one')
    partitions = split_participants(joined, 42)
    memberships = pd.concat([part[['participant_id']].drop_duplicates()
                             for part in partitions.values()])
    assert memberships.participant_id.is_unique
    assert len(memberships) == 30
    assert sum(len(part) for part in partitions.values()) == 30 * WINDOWS_PER_MOTHER


def test_direction_uses_inclusive_four_point_change():
    values = _direction(np.array([16, 16, 16, 16, 16]), [12, 13, 16, 19, 20])
    assert values.tolist() == [0, 1, 1, 1, 2]


def test_experiment_artifact_cannot_be_loaded_by_runtime(tmp_path):
    destination = tmp_path / 'simulation'
    report = experiment(destination, seed=43, participants=100)
    assert report['data_kind'] == DATA_KIND
    assert report['clinical_promotion_allowed'] is False
    assert json.loads((destination / 'synthetic_report.json').read_text(encoding='utf-8')) == report
    artifact_path = destination / 'synthetic_experiment.joblib'
    artifact = joblib.load(artifact_path)
    assert artifact['clinical_promotion_allowed'] is False
    with pytest.raises(KeyError, match='pipeline'):
        ModelRuntime(artifact_path)
    with pytest.raises(ValueError, match='synthetic data'):
        prepare(destination, ForecastSpec('epds', 'study:en', 13))
