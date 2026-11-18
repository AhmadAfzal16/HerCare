import json

import numpy as np
import pandas as pd
import pytest

from scripts.download_research_data import FILES, verify
from training.research_features import (
    BINARY, CATEGORIES, EPDS_ITEMS, NUMERIC, PHQ_ITEMS, bangladesh_features, extract,
)


def source_row(**changes):
    result = {v[0]: next(iter(v[1])) for v in [*CATEGORIES.values(), *BINARY.values()]}
    result.update({v[0]: v[1] for v in NUMERIC.values()})
    result.update({item: "Not at all" for item in [*PHQ_ITEMS, *EPDS_ITEMS]})
    result.update({"sr": "1", "PHQ9 Score": "0", "PHQ9 Result": "Minimal",
                   "EPDS Score": "6", "EPDS Result": "Low"})
    result.update(changes)
    return result


def test_none_is_a_real_category_and_missing_is_not_zero():
    features, outcomes, audit = bangladesh_features(pd.DataFrame([source_row(
        **{"Education Level": "None", "Current monthly income": "None", "Age": "", "Trust and share feelings": ""})]))
    assert features.iloc[0]["education_source_category"] == "none"
    assert features.iloc[0]["income_source_bdt_band"] == "none"
    assert pd.isna(features.iloc[0]["age"])
    assert pd.isna(features.iloc[0]["can_confide"])
    assert outcomes.iloc[0]["phq9_research_label"] == 0
    assert audit["imputation_performed"] is False


def test_screen_answers_and_totals_never_enter_predictor_table():
    features, outcomes, audit = bangladesh_features(pd.DataFrame([source_row()]))
    assert not set(PHQ_ITEMS + EPDS_ITEMS + ["PHQ9 Score", "EPDS Score"]) & set(features)
    assert "phq9_source_total" in outcomes
    assert audit["clinical_promotion_allowed"] is False
    assert audit["future_outcome_available"] is False
    assert "children_source_band" in features and "parity" not in features
    assert "reported_birth_complication" in features and "preeclampsia" not in features


def test_inconsistent_total_or_category_is_quarantined_not_repaired():
    frame = pd.DataFrame([source_row(**{"PHQ9 Score": "10", "EPDS Result": "High"})])
    _, outcomes, audit = bangladesh_features(frame)
    assert outcomes.iloc[0]["phq9_source_total"] == 10
    assert outcomes.iloc[0]["phq9_reconstructed_source_total"] == 0
    assert pd.isna(outcomes.iloc[0]["phq9_research_label"])
    assert pd.isna(outcomes.iloc[0]["epds_research_label"])
    assert audit["questionnaire_checks"]["phq9"]["item_total_mismatch_or_missing_rows"] == 1


def test_unknown_codes_and_out_of_range_inputs_are_reported_as_missing():
    features, _, audit = bangladesh_features(pd.DataFrame([source_row(
        **{"Age": "200", "Recieved Support": "Excellent", PHQ_ITEMS[0]: "unknown"})]))
    assert np.isnan(features.iloc[0]["age"])
    assert pd.isna(features.iloc[0]["received_support_source_band"])
    assert audit["invalid_or_unknown_predictor_codes"]["received_support_source_band"] == {"excellent": 1}
    assert audit["questionnaire_checks"]["phq9"]["unknown_item_response_cells"] == 1


def test_full_measurement_duplicates_are_deduplicated_not_coarse_features():
    a, b, c = source_row(), source_row(sr="2"), source_row(sr="3", **{"EPDS Score": "7"})
    features, _, audit = bangladesh_features(pd.DataFrame([a, b, c]))
    assert len(features) == 2
    assert features["feature_group"].nunique() == 1
    assert audit["duplicate_full_measurement_rows_removed"] == 1


@pytest.mark.parametrize("change", [{"sr": ""}, {"sr": "1"}])
def test_ambiguous_source_ids_fail(change):
    frame = pd.DataFrame([source_row(), source_row(**change)])
    with pytest.raises(ValueError, match="record IDs"):
        bangladesh_features(frame)


def test_schema_drift_is_rejected():
    frame = pd.DataFrame([source_row()]).drop(columns="Family type")
    with pytest.raises(ValueError, match="Missing Bangladesh"):
        bangladesh_features(frame)


def test_export_is_separate_audited_and_does_not_overwrite(tmp_path):
    source = tmp_path / "source.csv"
    pd.DataFrame([source_row()]).to_csv(source, index=False)
    output = tmp_path / "new"
    extract("bangladesh_ppd_v3", source, output)
    assert json.loads((output / "audit.json").read_text())["extracted_rows"] == 1
    assert (output / "features.csv").exists() and (output / "outcomes.csv").exists()
    with pytest.raises(FileExistsError):
        extract("bangladesh_ppd_v3", source, output)


def test_download_validation_rejects_html_and_changed_content():
    with pytest.raises(ValueError, match="XLSX"):
        verify(b"<html>challenge</html>", FILES[2])
    with pytest.raises(ValueError, match="byte count"):
        verify(b"changed", FILES[0])
