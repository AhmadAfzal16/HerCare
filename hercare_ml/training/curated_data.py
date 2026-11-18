"""Audited PERI_DEP extraction with explicit source meanings and no label leakage."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass

import numpy as np
import pandas as pd

SOURCE_FIELDS = {
    "age": "Age",
    "number_of_children": "Total Number of Children",
    "education_level": "Female Education",
    "household_type": "Family System",
    "basic_needs_financial_strain": "Sufficient Money for Basic Needs",
    "mother_in_law_relationship_quality": "Relationship with Mother in-law",
}
RESEARCH_FEATURES = list(SOURCE_FIELDS)
APP_MATCHED_FEATURES = ["age", "education_level", "household_type"]
CATEGORICAL = ["education_level", "household_type"]
MISSING_TOKENS = {"", "null", "none", "nan", "na", "n/a", "?"}


@dataclass
class PreparedData:
    features: pd.DataFrame
    target: pd.Series
    groups: pd.Series
    record_hashes: pd.Series
    audit: dict


def _digest(values: list) -> str:
    canonical = [None if pd.isna(value) else str(value) for value in values]
    return hashlib.sha256(json.dumps(canonical, ensure_ascii=False,
                                    separators=(",", ":")).encode()).hexdigest()


def prepare_peri_dep(frame: pd.DataFrame) -> PreparedData:
    source = frame.copy()
    source.columns = [str(name).strip() for name in source.columns]
    if source.columns.duplicated().any():
        raise ValueError("Duplicate source column names after whitespace normalisation.")
    required = set(SOURCE_FIELDS.values()) | {"Labelling"}
    missing = sorted(required - set(source.columns))
    if missing:
        raise ValueError("Missing required PERI_DEP fields: " + ", ".join(missing))
    for column in source.columns:
        clean = source[column].astype("string").str.strip().str.casefold()
        source[column] = clean.mask(clean.isin(MISSING_TOKENS), pd.NA)
    raw_rows = len(source)
    target = source["Labelling"].map({"depressed": 1, "not": 0})
    bad_labels = target.isna()
    unknown_labels = source.loc[bad_labels, "Labelling"].fillna("<missing>").value_counts().to_dict()
    source = source.loc[~bad_labels].copy()
    # Deduplicate full source records, never just coarse demographic features.
    record_hashes = source.apply(lambda row: _digest(row.tolist()), axis=1)
    repeated = record_hashes.duplicated()
    source = source.loc[~repeated].copy()
    record_hashes = record_hashes.loc[~repeated].reset_index(drop=True)
    source = source.reset_index(drop=True)
    features = pd.DataFrame(index=source.index)
    invalid_counts = {}
    for field, source_name, lower, upper in [
        ("age", "Age", 15, 55), ("number_of_children", "Total Number of Children", 0, 20),
    ]:
        numeric = pd.to_numeric(source[source_name], errors="coerce")
        valid = numeric.notna() & np.isfinite(numeric) & numeric.between(lower, upper) & (numeric % 1 == 0)
        invalid_counts[field] = int((source[source_name].notna() & ~valid).sum())
        features[field] = numeric.where(valid, np.nan).astype(float)
    mappings = {
        "education_level": {"uneducated": "Uneducated", "primary": "Primary",
                            "middle": "Middle", "matric": "Matric",
                            "intermediate": "Intermediate", "graduation": "Graduation",
                            "masters": "Masters"},
        "household_type": {"joint": "joint", "nuclear": "nuclear"},
        "basic_needs_financial_strain": {"yes": 0.0, "no": 1.0},
        "mother_in_law_relationship_quality": {"poor": 0.0, "moderate": 0.5, "good": 1.0},
    }
    for field, mapping in mappings.items():
        original = source[SOURCE_FIELDS[field]]
        mapped = original.map(mapping)
        invalid_counts[field] = int((original.notna() & mapped.isna()).sum())
        features[field] = mapped.astype(object).where(mapped.notna(), np.nan) if field in CATEGORICAL else mapped.astype(float)
    features = features[RESEARCH_FEATURES]
    target = source["Labelling"].map({"depressed": 1, "not": 0}).astype(int).rename("current_screen_label")
    if target.nunique() != 2:
        raise ValueError("Training requires both known classes after label validation.")
    # With no participant IDs, block shared selected-feature patterns across splits.
    # This is a conservative proxy holdout; it does not prove participant independence.
    groups = features.apply(lambda row: _digest(row.tolist()), axis=1).rename("feature_group")
    audit = {
        "source_rows": raw_rows,
        "invalid_or_missing_target_rows_excluded": int(bad_labels.sum()),
        "unknown_target_codes": {str(key): int(value) for key, value in unknown_labels.items()},
        "normalised_duplicate_source_rows_removed": int(repeated.sum()),
        "curated_rows": len(features),
        "selected_features": RESEARCH_FEATURES,
        "source_mapping": SOURCE_FIELDS,
        "invalid_predictor_values_changed_to_missing": invalid_counts,
        "missing_predictor_values": {key: int(value) for key, value in features.isna().sum().items()},
        "class_counts": {str(key): int(value) for key, value in target.value_counts().sort_index().items()},
        "feature_groups": int(groups.nunique()),
        "groups_with_conflicting_labels": int(pd.DataFrame({"group": groups, "label": target})
                                              .groupby("group")["label"].nunique().gt(1).sum()),
        "excluded_from_predictors": [name for name in source.columns if name not in SOURCE_FIELDS.values()],
        "target_definition": "Source Labelling: depressed=1, not=0; current screening label, not future recovery",
        "participant_identity_available": False,
        "unavailable_for_recovery_training": [
            "participant_id", "index_timestamp", "followup_timestamp", "future_screening_score",
            "daily_mood_history", "sleep_records", "intervention_exposure", "independent_recovery_outcome",
        ],
    }
    return PreparedData(features, target, groups, record_hashes, audit)
