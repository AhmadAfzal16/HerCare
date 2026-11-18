import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LogisticRegression

from training.curated_data import APP_MATCHED_FEATURES, RESEARCH_FEATURES, prepare_peri_dep
from training.curated_train import build_pipeline, split_indices


def row(label="Depressed", **changes):
    result = {"Age": 28, "Total Number of Children": 2, "Female Education": "Matric",
              "Family System": "Joint", "Sufficient Money for Basic Needs": "Yes",
              "Relationship with Mother in-law": "Good", "Labelling": label,
              "Scalling": 14, "PHQ9_item": 3}
    result.update(changes)
    return result


def test_only_required_source_features_are_selected_and_target_leakage_is_excluded():
    prepared = prepare_peri_dep(pd.DataFrame([row(), row("Not ", Age=30)]))
    assert prepared.features.columns.tolist() == RESEARCH_FEATURES
    assert "Scalling" not in prepared.features
    assert "PHQ9_item" not in prepared.features
    assert "Labelling" not in prepared.features
    assert "number_of_children" not in APP_MATCHED_FEATURES
    assert "basic_needs_financial_strain" not in APP_MATCHED_FEATURES


def test_labels_are_never_imputed_or_silently_made_negative():
    prepared = prepare_peri_dep(pd.DataFrame([row(), row("Not ", Age=30),
                                            row("unknown", Age=31), row(None, Age=32)]))
    assert prepared.target.tolist() == [1, 0]
    assert prepared.audit["invalid_or_missing_target_rows_excluded"] == 2
    assert prepared.audit["unknown_target_codes"] == {"unknown": 1, "<missing>": 1}


def test_normalised_full_duplicates_are_removed_but_different_labels_are_retained():
    prepared = prepare_peri_dep(pd.DataFrame([row(), row(**{"Female Education": " Matric "}),
                                            row("Not ")]))
    assert len(prepared.features) == 2
    assert prepared.audit["normalised_duplicate_source_rows_removed"] == 1
    assert prepared.audit["groups_with_conflicting_labels"] == 1
    assert prepared.groups.nunique() == 1


def test_missing_unknown_and_invalid_feature_values_remain_missing_until_training():
    prepared = prepare_peri_dep(pd.DataFrame([
        row(Age=-1, **{"Female Education": "unknown", "Sufficient Money for Basic Needs": "?"}),
        row("Not ", Age=30, **{"Total Number of Children": -1}),
    ]))
    assert np.isnan(prepared.features.iloc[0]["age"])
    assert pd.isna(prepared.features.iloc[0]["education_level"])
    assert pd.isna(prepared.features.iloc[0]["basic_needs_financial_strain"])
    assert np.isnan(prepared.features.iloc[1]["number_of_children"])


def test_imputation_fits_training_only_and_marks_missing_test_inputs():
    prepared = prepare_peri_dep(pd.DataFrame([row(Age=20), row("Not", Age=30)]))
    pipeline = build_pipeline(RESEARCH_FEATURES, LogisticRegression(solver="liblinear"))
    pipeline.fit(prepared.features, prepared.target)
    preprocess = pipeline.named_steps["preprocess"]
    medians = preprocess.named_transformers_["numeric"].named_steps["impute"].statistics_
    assert medians[0] == 25
    heldout = prepared.features.iloc[[0]].copy()
    heldout.loc[:, "age"] = np.nan
    heldout.loc[:, "education_level"] = "Unseen qualification"
    transformed = preprocess.transform(heldout)
    assert np.isfinite(transformed).all()
    flag = list(preprocess.get_feature_names_out()).index("missingness__missingindicator_age")
    assert transformed[0, flag] == 1
    assert medians[0] == 25


def test_partitions_keep_shared_feature_patterns_together_and_preserve_both_classes():
    frames = [row("Depressed" if index % 2 else "Not", Age=20 + index % 30,
                  **{"Total Number of Children": index // 30, "Scalling": index})
              for index in range(120)]
    prepared = prepare_peri_dep(pd.DataFrame(frames))
    parts = split_indices(prepared.target, prepared.groups)
    assert sum(len(indices) for indices in parts.values()) == len(prepared.target)
    group_sets = [set(prepared.groups.iloc[indices]) for indices in parts.values()]
    assert not group_sets[0] & group_sets[1]
    assert not group_sets[0] & group_sets[2]
    assert not group_sets[1] & group_sets[2]
    assert all(prepared.target.iloc[indices].nunique() == 2 for indices in parts.values())


def test_duplicate_column_names_and_single_class_datasets_fail_closed():
    duplicate = pd.DataFrame([row(), row("Not")])
    duplicate[" Age "] = 30
    with pytest.raises(ValueError, match="Duplicate source"):
        prepare_peri_dep(duplicate)
    with pytest.raises(ValueError, match="both known classes"):
        prepare_peri_dep(pd.DataFrame([row(), row("missing")]))
