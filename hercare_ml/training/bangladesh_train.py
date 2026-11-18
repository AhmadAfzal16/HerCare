"""Research comparison on integrity-checked first-year Bangladesh screening data.

This is current-screen association, NOT a future recovery model or external
validation of the Pakistani live artifact (feature meanings differ).
"""
import argparse
import json
from pathlib import Path

import joblib
import pandas as pd
from sklearn.calibration import CalibratedClassifierCV
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.frozen import FrozenEstimator
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.utils.class_weight import compute_sample_weight

from training.curated_train import evaluate, split_indices


def train(directory: Path, output: Path):
    if output.exists():
        raise FileExistsError('Use a new experiment directory')
    audit = json.loads((directory / 'audit.json').read_text())
    if audit.get('source_id') != 'bangladesh_ppd_v3':
        raise ValueError('Require the reviewed Bangladesh extraction')
    x = pd.read_csv(directory / 'features.csv', keep_default_na=False, na_values=[''])
    outcomes = pd.read_csv(directory / 'outcomes.csv', keep_default_na=False, na_values=[''])
    joined = x.merge(outcomes[['source_id', 'source_record_id', 'phq9_research_label']],
                     on=['source_id', 'source_record_id'], validate='one_to_one')
    valid = joined.phq9_research_label.notna() & joined.postpartum_source_band.isin(['0_6_months', '6_12_months'])
    frame = joined.loc[valid].reset_index(drop=True)
    target = frame.phq9_research_label.astype(int)
    parts = split_indices(target, frame.feature_group)
    results = {'scope': 'current_source_phq9_screen_association', 'horizon_days': None,
               'target': 'source PHQ-9 score >=10, passing item-total and category checks',
               'eligible_rows': len(frame), 'excluded_label_or_population_rows': int((~valid).sum()),
               'class_counts': {str(k): int(v) for k, v in target.value_counts().items()},
               'models': {}, 'deployment_eligible': False,
               'limitations': ['Cross-population, nonclinical labels; no future outcomes.',
                              'No verified subject identities; selected-feature grouping is only a conservative proxy.',
                              'Source support/education/income categories are not identical to app fields.']}
    output.mkdir(parents=True, exist_ok=False)
    for profile, columns in [('source_context', audit['predictor_columns']),
                             ('shared_context', ['age', 'household_type', 'cesarean', 'baby_female'])]:
        categories = [c for c in columns if frame[c].dtype == object]
        numeric = [c for c in columns if c not in categories]
        for name, estimator in [('logistic', LogisticRegression(C=.5, max_iter=2000, solver='liblinear', random_state=42)),
                                ('boosting', GradientBoostingClassifier(n_estimators=100, max_depth=2, random_state=42))]:
            prep = ColumnTransformer([
                ('numeric', Pipeline([('impute', SimpleImputer(strategy='median', add_indicator=True)), ('scale', StandardScaler())]), numeric),
                ('categorical', Pipeline([('impute', SimpleImputer(strategy='constant', fill_value='__missing__')),
                                          ('encode', OneHotEncoder(handle_unknown='ignore', sparse_output=False))]), categories)])
            base = Pipeline([('preprocess', prep), ('model', estimator)])
            fit, calibration, test = [parts[key] for key in ['train', 'calibration', 'test']]
            base.fit(frame[columns].iloc[fit], target.iloc[fit], model__sample_weight=compute_sample_weight('balanced', target.iloc[fit]))
            calibrated = CalibratedClassifierCV(FrozenEstimator(base), method='sigmoid')
            calibrated.fit(frame[columns].iloc[calibration], target.iloc[calibration])
            key = profile + '_' + name
            metrics = evaluate(target.iloc[test], calibrated.predict_proba(frame[columns].iloc[test])[:, 1], .5)
            results['models'][key] = metrics
            joblib.dump({'research_pipeline': calibrated, 'feature_names': columns, 'deployment_eligible': False}, output / f'{key}.joblib')
    results['partitions'] = {k: len(v) for k, v in parts.items()}
    (output / 'report.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(json.dumps({k: {'accuracy': v['accuracy'], 'auc': v['roc_auc']} for k, v in results['models'].items()}, indent=2))
    return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    train(args.input_dir, args.output_dir)
