"""Re-evaluate the checked-in artifact without retraining or printing source rows."""
import hashlib
import json
import pathlib
import sys

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, balanced_accuracy_score, confusion_matrix, roc_auc_score
from sklearn.model_selection import train_test_split

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from training.train import prepare_peri_dep  # noqa: E402


def main():
    root = pathlib.Path(__file__).resolve().parents[1]
    source = root / 'data/raw/peri_dep_dataset.csv'
    artifact = joblib.load(root / 'artifacts/peri_dep_baseline.joblib')
    metadata = artifact['metadata']
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != metadata['dataset_sha256']:
        raise ValueError('Dataset does not match the trained artifact')
    frame = pd.read_csv(source, encoding='utf-8-sig')
    x, y = prepare_peri_dep(frame)
    x_train, x_test, _, y_test = train_test_split(x, y, test_size=.2, random_state=42, stratify=y)
    probability = artifact['pipeline'].predict_proba(x_test)[:, 1]
    predicted = probability >= .5
    signatures = pd.util.hash_pandas_object(x, index=False)
    overlap = signatures.loc[x_test.index].isin(set(signatures.loc[x_train.index]))
    output = {
        'dataset_hash_matches': True, 'rows': len(frame), 'train_rows': len(x_train), 'test_rows': len(x_test),
        'accuracy': accuracy_score(y_test, predicted), 'balanced_accuracy': balanced_accuracy_score(y_test, predicted),
        'roc_auc': roc_auc_score(y_test, probability), 'confusion_matrix_true_rows_predicted_columns': confusion_matrix(y_test, predicted).tolist(),
        'always_positive_accuracy': float(y_test.mean()),
        'test_rows_with_feature_pattern_also_in_training': int(overlap.sum()),
        'note': 'Repeated six-feature patterns are not proof of duplicate participants or label leakage.',
        'saved_accuracy_matches': bool(np.isclose(accuracy_score(y_test, predicted), metadata['metrics']['classification_report']['accuracy'])),
    }
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()
