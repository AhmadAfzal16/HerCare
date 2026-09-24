"""Reproducible HerCare model training.

The public PERI_DEP data is cross-sectional. It can train the baseline model,
but it cannot truthfully train a two-week trajectory target. The trajectory
mode therefore requires a prospectively collected, independently labelled
HerCare export containing ``depressed_in_14d``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
from datetime import UTC, datetime

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier, VotingClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score,
    balanced_accuracy_score,
    brier_score_loss,
    classification_report,
    f1_score,
    roc_auc_score,
)
from sklearn.model_selection import train_test_split
from sklearn.neural_network import MLPClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

MODEL_VERSION = "m4-ensemble-v1"
BASELINE_FEATURES = [
    "age",
    "parity",
    "education_level",
    "household_type",
    "financial_strain",
    "support_quality",
]
TRAJECTORY_FEATURES = BASELINE_FEATURES + [
    "cesarean",
    "baby_female",
    "obstetric_complications",
    "latest_epds_score",
    "latest_phq9_score",
    "average_mood",
    "mood_slope",
    "average_energy",
    "average_sleep_quality",
    "average_social_support",
    "negative_notification_ratio",
    "distress_notification_ratio",
    "abuse_notification_ratio",
    "average_screen_minutes",
    "average_social_minutes",
    "average_late_night_minutes",
    "telemetry_days",
    "mood_days",
]
CATEGORICAL = ["education_level", "household_type"]


def _normalise_columns(frame: pd.DataFrame) -> pd.DataFrame:
    frame = frame.copy()
    frame.columns = [str(column).strip() for column in frame.columns]
    return frame


def prepare_peri_dep(frame: pd.DataFrame) -> tuple[pd.DataFrame, pd.Series]:
    """Map the public dataset to fields HerCare can collect without leakage."""
    frame = _normalise_columns(frame)
    required = {
        "Age",
        "Total Number of Children",
        "Female Education",
        "Family System",
        "Sufficient Money for Basic Needs",
        "Relationship with Mother in-law",
        "Labelling",
    }
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise ValueError(f"PERI_DEP columns missing: {', '.join(missing)}")

    features = pd.DataFrame(
        {
            "age": pd.to_numeric(frame["Age"], errors="coerce"),
            "parity": pd.to_numeric(frame["Total Number of Children"], errors="coerce"),
            "education_level": frame["Female Education"].astype("string").str.strip(),
            "household_type": frame["Family System"].astype("string").str.strip().str.lower(),
            "financial_strain": (
                frame["Sufficient Money for Basic Needs"]
                .astype("string")
                .str.strip()
                .str.lower()
                .map({"yes": 0.0, "no": 1.0})
            ),
            "support_quality": (
                frame["Relationship with Mother in-law"]
                .astype("string")
                .str.strip()
                .str.lower()
                .map({"poor": 0.0, "moderate": 0.5, "good": 1.0})
            ),
        }
    )
    target = (
        frame["Labelling"].astype("string").str.strip().str.lower() == "depressed"
    ).astype(int)
    return features, target


def prepare_trajectory(frame: pd.DataFrame) -> tuple[pd.DataFrame, pd.Series]:
    frame = _normalise_columns(frame)
    required = set(TRAJECTORY_FEATURES + ["depressed_in_14d"])
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise ValueError(
            "A trajectory model requires prospective 14-day labels. Missing: "
            + ", ".join(missing)
        )
    target = pd.to_numeric(frame["depressed_in_14d"], errors="raise").astype(int)
    if set(target.unique()).difference({0, 1}):
        raise ValueError("depressed_in_14d must contain only 0 and 1")
    return frame[TRAJECTORY_FEATURES].copy(), target


def build_pipeline(feature_names: list[str]) -> Pipeline:
    categorical = [name for name in CATEGORICAL if name in feature_names]
    numeric = [name for name in feature_names if name not in categorical]
    preprocessor = ColumnTransformer(
        [
            (
                "numeric",
                Pipeline(
                    [
                        ("impute", SimpleImputer(strategy="median", add_indicator=True)),
                        ("scale", StandardScaler()),
                    ]
                ),
                numeric,
            ),
            (
                "categorical",
                Pipeline(
                    [
                        ("impute", SimpleImputer(strategy="most_frequent")),
                        (
                            "encode",
                            OneHotEncoder(handle_unknown="ignore", min_frequency=5),
                        ),
                    ]
                ),
                categorical,
            ),
        ],
        verbose_feature_names_out=False,
    )
    ensemble = VotingClassifier(
        estimators=[
            (
                "logistic",
                LogisticRegression(max_iter=1000, class_weight="balanced", random_state=42),
            ),
            (
                "forest",
                RandomForestClassifier(
                    n_estimators=300,
                    min_samples_leaf=8,
                    class_weight="balanced_subsample",
                    n_jobs=-1,
                    random_state=42,
                ),
            ),
            ("boosting", GradientBoostingClassifier(random_state=42)),
            (
                "neural_network",
                MLPClassifier(
                    hidden_layer_sizes=(32, 16),
                    early_stopping=True,
                    max_iter=350,
                    random_state=42,
                ),
            ),
        ],
        voting="soft",
        flatten_transform=True,
    )
    return Pipeline([("preprocess", preprocessor), ("ensemble", ensemble)])


def train(input_path: pathlib.Path, output_path: pathlib.Path, task: str) -> dict:
    frame = pd.read_csv(input_path, encoding="utf-8-sig")
    if task == "baseline":
        features, target = prepare_peri_dep(frame)
        feature_names = BASELINE_FEATURES
        scope = "cross_sectional_baseline"
        horizon_days = None
    else:
        features, target = prepare_trajectory(frame)
        feature_names = TRAJECTORY_FEATURES
        scope = "two_week_trajectory"
        horizon_days = 14

    x_train, x_test, y_train, y_test = train_test_split(
        features,
        target,
        test_size=0.2,
        random_state=42,
        stratify=target,
    )
    pipeline = build_pipeline(feature_names)
    pipeline.fit(x_train, y_train)
    probabilities = pipeline.predict_proba(x_test)[:, 1]
    predicted = (probabilities >= 0.5).astype(int)
    metrics = {
        "roc_auc": float(roc_auc_score(y_test, probabilities)),
        "average_precision": float(average_precision_score(y_test, probabilities)),
        "balanced_accuracy": float(balanced_accuracy_score(y_test, predicted)),
        "f1": float(f1_score(y_test, predicted)),
        "brier_score": float(brier_score_loss(y_test, probabilities)),
        "classification_report": classification_report(
            y_test, predicted, output_dict=True, zero_division=0
        ),
        "test_rows": int(len(y_test)),
    }
    metadata = {
        "model_version": MODEL_VERSION,
        "model_scope": scope,
        "horizon_days": horizon_days,
        "feature_names": feature_names,
        "trained_at": datetime.now(UTC).isoformat(),
        "training_rows": int(len(x_train)),
        "positive_rate": float(target.mean()),
        "dataset_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        "dataset_citation": "PERI_DEP Dataset, Zenodo record 11403247, CC BY 4.0",
        "metrics": metrics,
        "limitations": (
            "Cross-sectional association only; must not be described as a future trajectory."
            if task == "baseline"
            else "Requires prospective external validation before clinical deployment."
        ),
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump({"pipeline": pipeline, "metadata": metadata}, output_path)
    output_path.with_suffix(".json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True), encoding="utf-8"
    )
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--task", choices=["baseline", "trajectory"], required=True)
    args = parser.parse_args()
    metadata = train(args.input, args.output, args.task)
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()

