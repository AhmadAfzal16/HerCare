"""Small local bilingual/roman-Urdu sparse retrieval with trained relevance ranking."""
import hashlib
import json
import os
from functools import lru_cache
from pathlib import Path
import unicodedata

import joblib
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression

ROOT = Path(__file__).resolve().parents[2]
KNOWLEDGE = ROOT / 'knowledge' / 'chatbot' / 'cards.json'


def normalize(value: str) -> str:
    return ' '.join(unicodedata.normalize('NFKC', value).casefold().split())


def load_cards():
    content = json.loads(KNOWLEDGE.read_text(encoding='utf-8'))
    return content['cards'], hashlib.sha256(KNOWLEDGE.read_bytes()).hexdigest()


class Retriever:
    def __init__(self, cards: list, *, artifact=None):
        self.cards = cards
        if artifact:
            self.word, self.char, self.word_index, self.char_index, self.ranker = [artifact[k]
                for k in ['word', 'char', 'word_index', 'char_index', 'ranker']]
            self.selected_method = artifact['selected_method']
        else:
            texts = [normalize(' '.join([c['title'], *c['responses'].values(),
                          *[q for values in c['queries'].values() for q in values[:2]]])) for c in cards]
            self.word = TfidfVectorizer(ngram_range=(1, 2), sublinear_tf=True)
            self.char = TfidfVectorizer(analyzer='char_wb', ngram_range=(3, 5), sublinear_tf=True)
            self.word_index, self.char_index = self.word.fit_transform(texts), self.char.fit_transform(texts)
            self.ranker = None
            self.selected_method = 'hybrid'

    def features(self, query):
        text = normalize(query)
        word = (self.word_index @ self.word.transform([text]).T).toarray().ravel()
        char = (self.char_index @ self.char.transform([text]).T).toarray().ravel()
        return np.column_stack([word, char, word * char])

    def scores(self, query, method=None):
        method = method or self.selected_method
        values = self.features(query)
        if method == 'word':
            return values[:, 0]
        if method == 'char':
            return values[:, 1]
        if method == 'trained' and self.ranker is not None:
            return self.ranker.predict_proba(values)[:, 1]
        return .5 * (values[:, 0] + values[:, 1])

    def search(self, query, limit=3):
        scores = self.scores(query)
        # Absolute lexical evidence is separate from the small authored-data ranker's score.
        evidence = self.features(query)[:, :2].max(axis=1)
        return [(self.cards[i], float(scores[i]), float(evidence[i]))
                for i in np.argsort(-scores)[:limit] if evidence[i] >= .12]

    def fit_ranker(self):
        features, labels = [], []
        for i, card in enumerate(self.cards):
            for values in card['queries'].values():
                for text in values[:2]:
                    features.extend(self.features(text))
                    labels.extend(int(j == i) for j in range(len(self.cards)))
        self.ranker = LogisticRegression(C=4, class_weight='balanced', max_iter=1000, random_state=42)
        self.ranker.fit(np.asarray(features), np.asarray(labels))
        return len(labels)


@lru_cache(maxsize=1)
def retriever():
    cards, digest = load_cards()
    default = ROOT / 'artifacts' / 'chatbot' / 'retrieval_v1' / 'retrieval.joblib'
    path = Path(os.getenv('CHATBOT_RETRIEVER_PATH', str(default)))
    if path.is_file():
        artifact = joblib.load(path)  # Operator-owned local artifact only.
        if artifact.get('knowledge_sha256') != digest:
            raise ValueError('Knowledge changed; rebuild and evaluate the retrieval artifact')
        return Retriever(cards, artifact=artifact)
    # Functional transparent lexical fallback; no hidden runtime training/download.
    return Retriever(cards)
