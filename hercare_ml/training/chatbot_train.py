"""Train a custom retrieval relevance ranker; NOT a pretrained LLM fine-tune.

Original authored application/support queries are engineering fixtures, not
clinical dialogue or independent patient validation. Nothing private is read.
"""
import argparse
import json
from pathlib import Path
import joblib
import numpy as np
from app.chatbot.retrieval import Retriever, load_cards


def evaluate(model, query_position, method):
    rows = []
    for target, card in enumerate(model.cards):
        for language, examples in card['queries'].items():
            scores = model.scores(examples[query_position], method)
            order = np.argsort(-scores)
            rank = int(np.where(order == target)[0][0]) + 1
            rows.append({'language': language, 'target': card['id'], 'rank': rank})
    return {'queries': len(rows), 'recall_at_1': sum(r['rank'] == 1 for r in rows) / len(rows),
            'recall_at_3': sum(r['rank'] <= 3 for r in rows) / len(rows),
            'mrr': sum(1 / r['rank'] for r in rows) / len(rows),
            'language_recall_at_1': {lang: np.mean([r['rank'] == 1 for r in rows if r['language'] == lang]).item()
                                     for lang in ['en', 'ur', 'roman_ur']}, 'cases': rows}


def train(output):
    if output.exists():
        raise FileExistsError('Use a fresh experiment directory')
    cards, digest = load_cards()
    model = Retriever(cards)
    pairs = model.fit_ranker()
    report = {'task': 'hercare_retrieval_relevance', 'knowledge_sha256': digest,
              'training_query_count': len(cards) * 3 * 2, 'training_pair_count': pairs,
              'data_kind': 'original_authored_engineering_examples', 'clinical_validation': False,
              'llm_finetuned': False, 'validation': {}, 'test': {},
              'limitations': ['Small same-author topic paraphrases, not independent clinical or patient evaluation.',
                             'Only lexical similarity; no claim of semantic embedding/RAG superiority.',
                             'Final release requires independently authored multilingual and safety evaluation.']}
    for method in ['word', 'char', 'hybrid', 'trained']:
        report['validation'][method] = evaluate(model, 2, method)
    chosen = max(report['validation'], key=lambda method: report['validation'][method]['mrr'])
    # Report all declared baselines without using test results for selection.
    for method in ['word', 'char', 'hybrid', 'trained']:
        report['test'][method] = evaluate(model, 3, method)
    report['validation_selected_method'] = chosen
    # Fit ranker is provisioned, but retain selected method explicitly for inference.
    artifact = {key: getattr(model, key) for key in ['word', 'char', 'word_index', 'char_index', 'ranker']}
    artifact.update(knowledge_sha256=digest, metadata=report, selected_method=chosen)
    output.mkdir(parents=True, exist_ok=False)
    joblib.dump(artifact, output / 'retrieval.joblib', compress=3)
    (output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({m: {k: v for k, v in r.items() if k != 'cases'} for m, r in report['test'].items()}, indent=2))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    train(parser.parse_args().output_dir)
