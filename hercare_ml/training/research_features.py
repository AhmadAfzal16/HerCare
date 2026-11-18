"""Source-specific extraction; no pooling, imputation, or same-screen predictors.

Run: python -m training.research_features --source bangladesh_ppd_v3
     --input data/raw/bangladesh_ppd_v3/PPD_dataset_v3.csv
     --output-dir data/processed/bangladesh_v3_review
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd

from training.curated_data import prepare_peri_dep

# The spelling and distinctions here come from the downloaded CSV, not guessed
# column positions. Education, child-count bands and relationship codes retain
# their source meaning rather than becoming Pakistani app dropdown values.
NUMERIC = {"age": ("Age", 18, 55), "pregnancy_count": ("Number of the latest pregnancy", 1, 20)}
CATEGORIES = {
    "education_source_category": ("Education Level", {
        "none": "none", "primary school": "primary", "high school": "high_school",
        "college": "college", "university": "university"}),
    "household_type": ("Family type", {"joint": "joint", "nuclear": "nuclear"}),
    "children_source_band": ("Total children", {"one": "one", "two": "two", "more than two": "more_than_two"}),
    "postpartum_source_band": ("Age of newborn", {
        "0 to 6 months": "0_6_months", "6 months to 1 year": "6_12_months",
        "1 year to 1.5 year": "12_18_months", "older than 1.5 year": "18_24_months"}),
    "in_law_relationship_source_category": ("Relationship with the in-laws", {
        x: x for x in ["bad", "poor", "neutral", "good", "friendly"]}),
    "husband_relationship_source_category": ("Relationship with husband", {
        x: x for x in ["bad", "poor", "neutral", "good", "friendly"]}),
    "received_support_source_band": ("Recieved Support", {x: x for x in ["high", "medium", "low"]}),
    "income_source_bdt_band": ("Current monthly income", {x: x.replace(" ", "_") for x in [
        "none", "less than 5000", "5000 to 10000", "10000 to 20000", "20000 to 30000", "more than 30000"]}),
    "pregnancy_loss_source_category": ("History of pregnancy loss", {
        "none": "none", "miscarriage": "miscarriage", "still-born delivery": "stillbirth"}),
}
YES_NO = {"yes": 1.0, "no": 0.0}
BINARY = {
    "cesarean": ("Mode of delivery", {"caesarean section": 1.0, "normal delivery": 0.0}),
    "baby_female": ("Gender of newborn", {"girl": 1.0, "boy": 0.0}),
    "reported_birth_complication": ("Birth compliancy", YES_NO),
    "pregnancy_planned": ("Pregnancy plan", YES_NO),
    "regular_prenatal_checkups": ("Regular checkups", YES_NO),
    "fear_of_pregnancy": ("Fear of pregnancy", YES_NO),
    "reported_abuse": ("Abuse", {**YES_NO, "none": 0.0}),
    "can_confide": ("Trust and share feelings", YES_NO),
    "prenatal_phq2_positive": ("Depression during pregnancy (PHQ2)", {"positive": 1.0, "negative": 0.0}),
    "prepregnancy_phq2_positive": ("Depression before pregnancy (PHQ2)", {"positive": 1.0, "negative": 0.0}),
}
PHQ_ITEMS = [
    "Little interest or pleasure in doing things", "Feeling down, depressed, or hopeless",
    "Trouble falling or staying asleep, or sleeping too much", "Feeling tired or having little energy",
    "Poor appetite or overeating", "Feeling bad about yourself or that you are a failure or have let yourself or your family down",
    "rouble concentrating on things", "Moving or speaking or restlessness",
    "Thoughts that you would be better off dead, or of hurting yourself",
]
EPDS_ITEMS = [
    "You have been able to laugh and see the funny side of things",
    "You have looked forward with enjoyment to things", "You have blamed myself unnecessarily when things went wrong",
    "You have been anxious or worried for no good reason", "You have felt scared or panicky for no good reason",
    "Things have been getting to you", "You have been so unhappy that you have had difficulty sleeping",
    "You have felt sad or miserable", "You have been so unhappy that you have been crying",
    "The thought of harming yourself has occurred",
]
ITEM_CODES = {"not at all": 0, "several days": 1, "মাঝে মধ্যে (several days)": 1,
              "around half the days": 2, "more than half the days": 2, "nearly every day": 3}


def normalise(frame: pd.DataFrame) -> pd.DataFrame:
    clean = frame.copy()
    clean.columns = [str(name).strip() for name in clean.columns]
    if clean.columns.duplicated().any():
        raise ValueError("Duplicate source column names")
    for name in clean:
        values = clean[name].astype("string").str.strip().str.casefold()
        # 'None' is a real category (no income, education, loss), NOT null.
        clean[name] = values.mask(values.isin(["", "null", "nan", "n/a", "na"]), pd.NA)
    return clean


def row_hashes(frame: pd.DataFrame) -> pd.Series:
    return frame.apply(lambda row: hashlib.sha256(json.dumps(
        [None if pd.isna(x) else str(x) for x in row], separators=(",", ":"),
        ensure_ascii=False).encode()).hexdigest(), axis=1)


def numeric(values: pd.Series, low: int, high: int) -> pd.Series:
    numbers = pd.to_numeric(values, errors="coerce")
    return numbers.where(np.isfinite(numbers) & numbers.between(low, high) & (numbers % 1 == 0)).astype(float)


def bangladesh_features(frame: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    clean = normalise(frame)
    required = {v[0] for v in [*NUMERIC.values(), *CATEGORIES.values(), *BINARY.values()]} | set(
        PHQ_ITEMS + EPDS_ITEMS + ["sr", "PHQ9 Score", "EPDS Score", "PHQ9 Result", "EPDS Result"])
    missing = sorted(required - set(clean))
    if missing:
        raise ValueError("Missing Bangladesh v3 columns: " + ", ".join(missing))
    if clean["sr"].isna().any() or clean["sr"].duplicated().any():
        raise ValueError("Missing or duplicate source record IDs; participant identity cannot be inferred")
    hashes = row_hashes(clean.drop(columns="sr"))
    duplicates = hashes.duplicated()
    clean = clean.loc[~duplicates].reset_index(drop=True)
    hashes = hashes.loc[~duplicates].reset_index(drop=True)
    features = pd.DataFrame(index=clean.index)
    unknown = {}
    source_mapping = {}
    for name, (column, low, high) in NUMERIC.items():
        source_mapping[name] = column
        features[name] = numeric(clean[column], low, high)
        unknown[name] = int((clean[column].notna() & features[name].isna()).sum())
    for name, (column, codes) in {**CATEGORIES, **BINARY}.items():
        source_mapping[name] = column
        mapped = clean[column].map(codes)
        unknown[name] = clean.loc[clean[column].notna() & mapped.isna(), column].value_counts().to_dict()
        features[name] = mapped.where(mapped.notna(), np.nan)
    metadata = pd.DataFrame({"source_id": "bangladesh_ppd_v3", "source_record_id": clean["sr"],
                             "record_hash": hashes, "feature_group": row_hashes(features)})
    outcomes = metadata.copy()
    findings = {}
    for instrument, columns, maximum in [("phq9", PHQ_ITEMS, 27), ("epds", EPDS_ITEMS, 30)]:
        items = clean[columns].apply(lambda x: x.map(ITEM_CODES)).astype(float)
        if instrument == "epds":
            items.iloc[:, :2] = 3 - items.iloc[:, :2]
        reconstructed = items.sum(axis=1, min_count=len(columns))
        total_name = "PHQ9 Score" if instrument == "phq9" else "EPDS Score"
        provided = numeric(clean[total_name], 0, maximum)
        consistent = provided.notna() & reconstructed.notna() & provided.eq(reconstructed)
        result_name = "PHQ9 Result" if instrument == "phq9" else "EPDS Result"
        if instrument == "epds":
            expected_category = provided.map(lambda x: None if pd.isna(x) else "low" if x <= 8 else "medium" if x <= 12 else "high")
        else:
            expected_category = provided.map(lambda x: None if pd.isna(x) else "minimal" if x <= 4 else "mild" if x <= 9 else "moderate" if x <= 14 else "moderately severe" if x <= 19 else "severe")
        category_match = clean[result_name].eq(expected_category).fillna(False)
        outcomes[f"{instrument}_source_total"] = provided
        outcomes[f"{instrument}_reconstructed_source_total"] = reconstructed
        outcomes[f"{instrument}_items_match_total"] = consistent
        outcomes[f"{instrument}_category_matches_codebook"] = category_match
        # Source-specific research outcome, not clinical diagnosis or future risk.
        valid = consistent & category_match
        outcomes[f"{instrument}_research_label"] = (provided >= (13 if instrument == "epds" else 10)).astype(float).where(valid)
        outcomes[f"{instrument}_source_safety_item"] = items.iloc[:, -1]
        findings[instrument] = {"invalid_or_missing_totals": int(provided.isna().sum()),
                               "unknown_item_response_cells": int(items.isna().sum().sum()),
                               "item_total_mismatch_or_missing_rows": int((~consistent).sum()),
                               "category_mismatch_rows": int((~category_match).sum()),
                               "usable_source_label_rows": int(valid.sum())}
    audit = {
        "source_id": "bangladesh_ppd_v3", "source_rows": len(frame), "extracted_rows": len(features),
        "duplicate_full_measurement_rows_removed": int(duplicates.sum()), "predictor_columns": list(features),
        "source_mapping": source_mapping, "invalid_or_unknown_predictor_codes": unknown,
        "missing_predictor_counts": {k: int(v) for k, v in features.isna().sum().items()},
        "questionnaire_checks": findings, "imputation_performed": False, "balancing_performed": False,
        "data_kind": "real_cross_sectional_research", "clinical_promotion_allowed": False,
        "participant_identity_verified": False, "future_outcome_available": False,
        "excluded_predictor_columns": [c for c in clean if c not in source_mapping.values()],
        "limitations": [
            "EPDS item response frequencies differ from the validated instrument; source codebook scoring is only an integrity check.",
            "PHQ-2 histories are retrospective self-reports, not prospectively observed trajectories.",
            "Newborn age is a band; no exact postpartum age or repeated dated recovery records exist.",
            "Source 'sr' identifies rows, not verified independent people; use feature-group holdouts and external validation.",
            "Education, income (BDT), child bands, support bands and in-law relationship do not equal current HerCare feature meanings.",
            "Disease categories do not identify preeclampsia, gestational diabetes or hemorrhage; no such diagnoses were inferred.",
            "Do not pool with PERI_DEP or train on outcomes.csv as predictor data.",
        ],
    }
    return pd.concat([metadata, features], axis=1), outcomes, audit


def extract(source: str, input_path: Path, output_dir: Path) -> dict:
    if output_dir.exists():
        raise FileExistsError("Choose a new output directory; previous research exports are preserved")
    # keep_default_na=False preserves real categories such as 'None'.
    frame = pd.read_csv(input_path, keep_default_na=False)
    if source == "bangladesh_ppd_v3":
        features, outcomes, audit = bangladesh_features(frame)
    elif source == "peri_dep":
        prepared = prepare_peri_dep(frame)
        metadata = pd.DataFrame({"source_id": "peri_dep", "record_hash": prepared.record_hashes,
                                 "feature_group": prepared.groups})
        features = pd.concat([metadata, prepared.features], axis=1)
        outcomes = pd.concat([metadata, prepared.target], axis=1)
        audit = {**prepared.audit, "data_kind": "real_cross_sectional_research",
                 "clinical_promotion_allowed": False, "future_outcome_available": False}
    else:
        raise ValueError("Unsupported source; a reviewed source-specific adapter is required")
    audit["input_sha256"] = hashlib.sha256(input_path.read_bytes()).hexdigest()
    output_dir.mkdir(parents=True, exist_ok=False)
    features.to_csv(output_dir / "features.csv", index=False)
    outcomes.to_csv(output_dir / "outcomes.csv", index=False)
    with (output_dir / "audit.json").open("x", encoding="utf-8") as stream:
        json.dump(audit, stream, indent=2, ensure_ascii=False, allow_nan=False)
    return audit


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", choices=["peri_dep", "bangladesh_ppd_v3"], required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    audit = extract(args.source, args.input, args.output_dir)
    print(json.dumps({"source": args.source, "rows": audit.get("extracted_rows", audit.get("curated_rows")),
                      "output": str(args.output_dir)}, indent=2))


if __name__ == "__main__":
    main()
