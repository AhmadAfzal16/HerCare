"""Train auditable research candidates without overwriting the live baseline.

Use: python -m training.curated_train --input data/raw/peri_dep_dataset.csv
     --output-dir artifacts/experiments/peri_dep_curated_20261008
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.calibration import CalibratedClassifierCV
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.frozen import FrozenEstimator
from sklearn.impute import MissingIndicator, SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (accuracy_score, average_precision_score, balanced_accuracy_score,
                             brier_score_loss, classification_report, confusion_matrix,
                             f1_score, roc_auc_score, roc_curve)
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.utils.class_weight import compute_sample_weight

from .curated_data import APP_MATCHED_FEATURES, CATEGORICAL, RESEARCH_FEATURES, prepare_peri_dep

VERSION = "curated-current-screen-research-v1"


def build_pipeline(features: list[str], estimator) -> Pipeline:
    categorical = [field for field in features if field in CATEGORICAL]
    numeric = [field for field in features if field not in categorical]
    preprocess = ColumnTransformer([
        ("numeric", Pipeline([("impute", SimpleImputer(strategy="median")),
                              ("scale", StandardScaler())]), numeric),
        ("categorical", Pipeline([
            ("impute", SimpleImputer(strategy="constant", fill_value="__missing__")),
            ("encode", OneHotEncoder(handle_unknown="ignore", min_frequency=5,
                                     sparse_output=False)),
        ]), categorical),
        ("missingness", MissingIndicator(features="all"), features),
    ])
    return Pipeline([("preprocess", preprocess), ("model", estimator)])


def split_indices(target: pd.Series, groups: pd.Series) -> dict[str, np.ndarray]:
    outer = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)
    remaining, test = next(outer.split(np.zeros(len(target)), target, groups))
    inner = StratifiedGroupKFold(n_splits=4, shuffle=True, random_state=43)
    fit_local, calibration_local = next(inner.split(
        np.zeros(len(remaining)), target.iloc[remaining], groups.iloc[remaining]))
    parts = {"train": remaining[fit_local], "calibration": remaining[calibration_local], "test": test}
    for name, indices in parts.items():
        if target.iloc[indices].nunique() != 2:
            raise ValueError(f"Both classes are required in the {name} partition.")
    for left, right in [("train", "calibration"), ("train", "test"), ("calibration", "test")]:
        if set(groups.iloc[parts[left]]) & set(groups.iloc[parts[right]]):
            raise ValueError("Feature-pattern groups crossed data partitions.")
    return parts


def evaluate(target, probabilities, threshold: float) -> dict:
    predictions = (probabilities >= threshold).astype(int)
    tn, fp, fn, tp = confusion_matrix(target, predictions, labels=[0, 1]).ravel()
    return {
        "threshold": threshold, "accuracy": float(accuracy_score(target, predictions)),
        "balanced_accuracy": float(balanced_accuracy_score(target, predictions)),
        "roc_auc": float(roc_auc_score(target, probabilities)),
        "average_precision": float(average_precision_score(target, probabilities)),
        "brier_score": float(brier_score_loss(target, probabilities)),
        "f1": float(f1_score(target, predictions, zero_division=0)),
        "sensitivity": float(tp / (tp + fn)), "specificity": float(tn / (tn + fp)),
        "confusion_matrix": [[int(tn), int(fp)], [int(fn), int(tp)]],
        "classification_report": classification_report(target, predictions, output_dict=True, zero_division=0),
    }


def research_threshold(target, probabilities) -> float:
    fpr, tpr, thresholds = roc_curve(target, probabilities)
    finite = np.isfinite(thresholds)
    valid_thresholds = thresholds[finite]
    gains = (tpr - fpr)[finite]
    return float(valid_thresholds[np.argmax(gains)])


def run(input_path: Path, output_dir: Path) -> dict:
    if output_dir.exists():
        raise ValueError("Choose a new experiment directory; existing results are never overwritten.")
    prepared = prepare_peri_dep(pd.read_csv(input_path, encoding="utf-8-sig"))
    parts = split_indices(prepared.target, prepared.groups)
    output_dir.mkdir(parents=True)
    audit = prepared.audit
    audit["dataset_sha256"] = hashlib.sha256(input_path.read_bytes()).hexdigest()
    audit["partitions"] = {
        name: {"rows": len(indices), "groups": int(prepared.groups.iloc[indices].nunique()),
               "class_counts": {str(key): int(value) for key, value in
                                prepared.target.iloc[indices].value_counts().sort_index().items()}}
        for name, indices in parts.items()
    }
    audit["split_method"] = "Normalised-source deduplication, then stratified six-feature-pattern group holdout"
    audit["split_warning"] = "No participant IDs: independent participants cannot be established; grouping is a conservative proxy."
    audit["class_balance_method"] = "Inverse-frequency sample weights, recalculated inside every training fold; validation/test distributions unchanged"
    audit["source"] = "PERI_DEP original dataset.csv, Zenodo record 11403247"
    selected = prepared.features.copy()
    selected["current_screen_label"] = prepared.target
    selected["source_record_hash"] = prepared.record_hashes
    selected["feature_group"] = prepared.groups
    partition_names = pd.Series(index=selected.index, dtype=object)
    for name, indices in parts.items():
        partition_names.iloc[indices] = name
    selected["partition"] = partition_names
    selected.to_csv(output_dir / "selected_features.csv", index=False)
    (output_dir / "data_audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
    estimators = {
        "logistic": LogisticRegression(C=0.5, solver="liblinear", max_iter=2000, random_state=42),
        "forest": RandomForestClassifier(n_estimators=200, min_samples_leaf=8, n_jobs=2, random_state=42),
        "boosting": GradientBoostingClassifier(n_estimators=150, max_depth=2, learning_rate=0.05, random_state=42),
    }
    summaries = {}
    for profile, feature_names in [("source_matched_six", RESEARCH_FEATURES),
                                   ("app_matched_three", APP_MATCHED_FEATURES)]:
        x = prepared.features[feature_names]
        y = prepared.target
        train_idx, calibration_idx, test_idx = (parts[name] for name in ("train", "calibration", "test"))
        if x.iloc[train_idx].isna().all().any():
            raise ValueError("An entirely missing training feature cannot be learned.")
        folds = list(StratifiedGroupKFold(n_splits=3, shuffle=True, random_state=44).split(
            x.iloc[train_idx], y.iloc[train_idx], prepared.groups.iloc[train_idx]))
        cv_scores = {}
        for name, estimator in estimators.items():
            scores = []
            for fit_local, validation_local in folds:
                fit_idx, validation_idx = train_idx[fit_local], train_idx[validation_local]
                candidate = build_pipeline(feature_names, clone(estimator))
                weights = compute_sample_weight("balanced", y.iloc[fit_idx])
                candidate.fit(x.iloc[fit_idx], y.iloc[fit_idx], model__sample_weight=weights)
                probabilities = candidate.predict_proba(x.iloc[validation_idx])[:, 1]
                scores.append(float(roc_auc_score(y.iloc[validation_idx], probabilities)))
            cv_scores[name] = {"roc_auc_folds": scores, "mean_roc_auc": float(np.mean(scores))}
            print(f"Completed training-fold evaluation: {profile}/{name}", flush=True)
        best_name = max(cv_scores, key=lambda name: cv_scores[name]["mean_roc_auc"])
        pipeline = build_pipeline(feature_names, clone(estimators[best_name]))
        training_weights = compute_sample_weight("balanced", y.iloc[train_idx])
        pipeline.fit(x.iloc[train_idx], y.iloc[train_idx], model__sample_weight=training_weights)
        calibrated = CalibratedClassifierCV(FrozenEstimator(pipeline), method="sigmoid")
        # Calibration preserves the observed (unbalanced) outcome distribution.
        calibrated.fit(x.iloc[calibration_idx], y.iloc[calibration_idx])
        threshold = research_threshold(y.iloc[calibration_idx],
                                       calibrated.predict_proba(x.iloc[calibration_idx])[:, 1])
        probabilities = calibrated.predict_proba(x.iloc[test_idx])[:, 1]
        preprocess = pipeline.named_steps["preprocess"]
        transformed_counts = {}
        for name, indices in parts.items():
            transformed = preprocess.transform(x.iloc[indices])
            if not np.isfinite(transformed).all():
                raise ValueError("Imputed/encoded training matrices contain non-finite values.")
            export = pd.DataFrame(transformed, columns=preprocess.get_feature_names_out())
            export["current_screen_label"] = y.iloc[indices].to_numpy()
            if name == "train":
                export["sample_weight"] = training_weights
            export.to_csv(output_dir / f"{profile}_{name}_processed.csv", index=False)
            transformed_counts[name] = {"rows": len(indices), "missing_matrix_values": 0}
        numeric_names = [field for field in feature_names if field not in CATEGORICAL]
        medians = preprocess.named_transformers_["numeric"].named_steps["impute"].statistics_
        metadata = {
            "model_version": VERSION, "profile": profile, "feature_names": feature_names,
            "model_scope": "cross_sectional_research", "horizon_days": None,
            "trained_at": datetime.now(UTC).isoformat(), "dataset_sha256": audit["dataset_sha256"],
            "selected_estimator": best_name, "training_cv": cv_scores,
            "class_balance_method": audit["class_balance_method"],
            "training_weight_sum_by_class": {str(label): float(training_weights[y.iloc[train_idx].to_numpy() == label].sum())
                                             for label in (0, 1)},
            "imputation": {"numeric_training_medians": dict(zip(numeric_names, medians.tolist())),
                           "categorical": "explicit __missing__ category", "missing_indicators": feature_names},
            "processed_partitions": transformed_counts, "calibration": "sigmoid on a separate held-out partition",
            "threshold_selection": "Maximise calibration-partition balanced accuracy; exploratory, not a clinical operating threshold",
            "test_default_threshold": evaluate(y.iloc[test_idx], probabilities, 0.5),
            "test_research_threshold": evaluate(y.iloc[test_idx], probabilities, threshold),
            "test_majority_class_accuracy": float(max(y.iloc[test_idx].mean(), 1 - y.iloc[test_idx].mean())),
            "deployment_eligible": False,
            "limitations": ["No future recovery outcomes", "No verified participant IDs or external validation",
                            "Threshold chosen on calibration data; report accuracy only on untouched test data",
                            "Six source features require exact measurements; three app features alone are limited"],
        }
        # Deliberately different key: the live ModelRuntime cannot load this as its production pipeline.
        joblib.dump({"research_pipeline": calibrated, "metadata": metadata}, output_dir / f"{profile}.joblib")
        (output_dir / f"{profile}.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
        summaries[profile] = metadata
    summary = {"audit": audit, "models": summaries, "live_artifact_replaced": False}
    (output_dir / "experiment_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    summary = run(args.input, args.output_dir)
    print(json.dumps({"audit": summary["audit"], "models": {
        name: {"selected_estimator": model["selected_estimator"],
               "test": model["test_research_threshold"]} for name, model in summary["models"].items()}}, indent=2))


if __name__ == "__main__":
    main()
