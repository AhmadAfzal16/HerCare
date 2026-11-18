"""Public-data annotation queue and independent two-reviewer consensus gate.

No production text is harvested. Distress annotations remain review data,
not a clinically validated model or automatic crisis operating threshold.
"""
import argparse
import json
from pathlib import Path

from training.sentiment_train import LABELS, clean_rows, load_sources


def consensus(entry: dict) -> dict | None:
    reviews = entry.get('reviews', [])
    if len(reviews) < 2 or len({r.get('reviewer_id') for r in reviews}) != len(reviews):
        return None
    if any(not r.get('reviewer_id') or r.get('sentiment') not in LABELS
           or r.get('distress') not in {'not_labelled', 'none', 'possible', 'high'} for r in reviews):
        return None
    if len({r['sentiment'] for r in reviews}) != 1 or len({r['distress'] for r in reviews}) != 1:
        return None
    return {**entry, 'review_status': 'independent_consensus',
            'reviewed_sentiment': reviews[0]['sentiment'], 'reviewed_distress': reviews[0]['distress'],
            'clinical_validation': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path)
    parser.add_argument('--reviewed-input', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite annotations')
    if bool(args.source_dir) == bool(args.reviewed_input):
        raise ValueError('Choose queue creation or reviewed consensus input')
    if args.source_dir:
        frame, _ = clean_rows(load_sources(args.source_dir))
        rows = []
        for (_, _), group in frame.groupby(['language', 'label']):
            for item in group.sample(n=min(30, len(group)), random_state=42).to_dict('records'):
                rows.append({**item, 'review_status': 'pending', 'reviews': [
                    {'reviewer_id': '', 'sentiment': None, 'distress': 'not_labelled'},
                    {'reviewer_id': '', 'sentiment': None, 'distress': 'not_labelled'}]})
    else:
        entries = [json.loads(line) for line in args.reviewed_input.read_text(encoding='utf-8').splitlines() if line.strip()]
        rows = [result for entry in entries if (result := consensus(entry)) is not None]
        print(f'{len(entries)-len(rows)} incomplete/disagreed rows remain pending')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf-8') as stream:
        for row in rows:
            stream.write(json.dumps(row, ensure_ascii=False) + '\n')
    print(f'Wrote {len(rows)} public review records; no clinical validation claimed')


if __name__ == '__main__':
    main()
