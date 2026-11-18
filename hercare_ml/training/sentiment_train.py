"""Audited lightweight sentiment baselines; never trains a clinical distress label."""
from __future__ import annotations
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import unicodedata
import zipfile

import joblib
import numpy as np
import pandas as pd
from sklearn.calibration import CalibratedClassifierCV
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.frozen import FrozenEstimator
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report, f1_score, log_loss
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline

LABELS = {'positive', 'negative', 'neutral'}


def normalise(text: str) -> str:
    return ' '.join(unicodedata.normalize('NFKC', text).casefold().split())


def load_sources(directory: Path) -> list[dict]:
    rows = []
    for name in ['english.zip', 'roman_urdu.zip', 'urdu.csv']:
        provenance = json.loads((directory / (name + '.provenance.json')).read_text(encoding='utf-8'))
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != provenance['sha256']:
            raise ValueError('Source checksum changed since licensed acquisition')
    with zipfile.ZipFile(directory / 'english.zip') as archive:
        for name in archive.namelist():
            if name.startswith('sentiment labelled sentences/') and name.endswith('_labelled.txt'):
                for line in archive.read(name).decode('utf-8-sig').splitlines():
                    parts = line.rsplit('\t', 1)
                    text, label = parts if len(parts) == 2 else (line, None)
                    rows.append({'text': text, 'label': {'0': 'negative', '1': 'positive'}.get(label),
                                 'language': 'en', 'source': 'uci_english', 'license': 'CC-BY-4.0'})
    with zipfile.ZipFile(directory / 'roman_urdu.zip') as archive:
        for row in csv.reader(io.StringIO(archive.read('Roman Urdu DataSet.csv').decode('utf-8-sig'))):
            if len(row) >= 2:
                rows.append({'text': row[0], 'label': row[1].strip().casefold(), 'language': 'roman_ur',
                             'source': 'uci_roman_urdu', 'license': 'CC-BY-4.0'})
    with (directory / 'urdu.csv').open(encoding='utf-8-sig', newline='') as stream:
        for row in csv.DictReader(stream):
            rows.append({'text': row['text'], 'label': row['sentiment'].strip().casefold(), 'language': 'ur',
                         'source': 'urdu_multidomain', 'license': 'CC0-1.0'})
    return rows


def clean_rows(rows: list[dict]) -> tuple[pd.DataFrame, dict]:
    valid, rejected = [], 0
    for row in rows:
        if not isinstance(row.get('text'), str) or row.get('label') not in LABELS or row.get('license') not in {'CC-BY-4.0', 'CC0-1.0'}:
            rejected += 1
            continue
        text = normalise(row['text'])
        if len(text) < 2 or len(text) > 10000:
            rejected += 1
            continue
        valid.append({**row, 'text': text, 'record_hash': hashlib.sha256(text.encode()).hexdigest()})
    frame = pd.DataFrame(valid)
    if frame.empty:
        raise ValueError('No licensed known-label observations')
    conflicts = frame.groupby(['language', 'record_hash'])['label'].nunique()
    conflict_keys = set(conflicts[conflicts > 1].index)
    conflicting = frame.apply(lambda r: (r['language'], r['record_hash']) in conflict_keys, axis=1)
    frame = frame.loc[~conflicting]
    before_dedup = len(frame)
    frame = frame.drop_duplicates(['language', 'record_hash']).reset_index(drop=True)
    return frame, {'raw_rows': len(rows), 'invalid_or_missing_label_text_license_rows': rejected,
                   'conflicting_label_rows_excluded': int(conflicting.sum()),
                   'duplicate_normalised_text_rows_removed': before_dedup - len(frame), 'curated_rows': len(frame)}


def train(directory: Path, output: Path) -> dict:
    if output.exists():
        raise FileExistsError('Choose a new sentiment artifact directory')
    frame, audit = clean_rows(load_sources(directory))
    output.mkdir(parents=True, exist_ok=False)
    report = {'audit': audit, 'models': {}, 'clinical_distress_model_trained': False}
    for language, records in frame.groupby('language', sort=True):
        records = records.reset_index(drop=True)
        if records.label.value_counts().min() < 20:
            report['models'][language] = {'status': 'insufficient_labelled_data', 'rows': len(records)}
            continue
        outer = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)
        remaining, test = next(outer.split(records.text, records.label, records.record_hash))
        inner = StratifiedGroupKFold(n_splits=4, shuffle=True, random_state=43)
        local_train, local_cal = next(inner.split(records.text.iloc[remaining], records.label.iloc[remaining], records.record_hash.iloc[remaining]))
        fit, calibration = remaining[local_train], remaining[local_cal]
        for split in [fit, calibration, test]:
            if records.label.iloc[split].nunique() != records.label.nunique():
                raise ValueError('Every NLP partition must contain all source classes')
        base = Pipeline([
            ('text', TfidfVectorizer(analyzer='char', ngram_range=(3, 5), min_df=2,
                                   max_features=40000, sublinear_tf=True, dtype=np.float32)),
            ('model', LogisticRegression(C=2, class_weight='balanced', max_iter=400, solver='lbfgs', random_state=42)),
        ])
        base.fit(records.text.iloc[fit], records.label.iloc[fit])
        model = CalibratedClassifierCV(FrozenEstimator(base), method='sigmoid')
        model.fit(records.text.iloc[calibration], records.label.iloc[calibration])
        probability = model.predict_proba(records.text.iloc[test])
        predicted = model.classes_[probability.argmax(axis=1)]
        metadata = {'model_version': f'sentiment-{language}-v2', 'task': 'general_sentiment', 'language': language,
                    'classes': model.classes_.tolist(), 'rows': len(records),
                    'partitions': {'train': len(fit), 'calibration': len(calibration), 'test': len(test)},
                    'accuracy': float(accuracy_score(records.label.iloc[test], predicted)),
                    'macro_f1': float(f1_score(records.label.iloc[test], predicted, average='macro')),
                    'log_loss': float(log_loss(records.label.iloc[test], probability, labels=model.classes_)),
                    'classification_report': classification_report(records.label.iloc[test], predicted, output_dict=True),
                    'algorithm': 'Character TF-IDF + balanced logistic regression + held-out sigmoid calibration',
                    'validation_status': 'public_benchmark_only', 'clinical_validation': False,
                    'abstention_threshold': .6, 'training_domains': sorted(records.source.unique().tolist()),
                    'input_provenance': [json.loads(path.read_text(encoding='utf-8')) for path in sorted(directory.glob('*.provenance.json'))],
                    'limitations': ['No postpartum/clinical distress labels or independent author identities.',
                                    'Public corpus accuracy is not journal/chat accuracy.',
                                    'Urdu-source annotation methodology is not documented; requires independent human audit.',
                                    'English corpus has no neutral class; uncertainty is abstention, not a trained neutral label.']}
        joblib.dump({'pipeline': model, 'vectorizer': base.named_steps['text'], 'metadata': metadata}, output / f'{language}.joblib', compress=3)
        (output / f'{language}.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
        assignments = records[['record_hash', 'source', 'label']].copy()
        assignments['partition'] = ''
        for name, positions in [('train', fit), ('calibration', calibration), ('test', test)]:
            assignments.loc[positions, 'partition'] = name
        assignments.to_json(output / f'{language}_partitions.jsonl', orient='records', lines=True)
        report['models'][language] = metadata
        print(language, len(records), 'accuracy', round(metadata['accuracy'], 4), 'macro_f1', round(metadata['macro_f1'], 4), flush=True)
    (output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    train(args.input_dir, args.output_dir)
