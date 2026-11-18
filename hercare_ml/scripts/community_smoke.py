"""Evaluate authored public engineering examples, never private community posts.

No training, threshold selection, service start or clinical accuracy claim. The
fixed 0.5 topic hint is examined, not promoted as a validated moderation cutoff.
"""
from __future__ import annotations

import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from app.community_moderation import ModerationRequest, moderate, metadata, ready


def main():
    import numpy as np
    source = json.loads((ROOT / "research/community_challenge.json").read_text(encoding="utf-8"))
    started = time.perf_counter()
    ready()
    load_seconds = time.perf_counter() - started
    results = []
    for case in source["cases"]:
        started = time.perf_counter()
        result = moderate(ModerationRequest(text=case["text"]))
        scores = result["scores"]
        expected = case["expected_topic"]
        ranked = sorted(scores, key=scores.get, reverse=True)
        results.append({"id": case["id"], "language": case["language"],
                        "seconds": round(time.perf_counter() - started, 4), "scores": scores,
                        "expected_topic": expected,
                        "expected_in_top3": expected in ranked[:3] if expected else None,
                        "expected_hint_at_0_5": scores[expected] >= 0.5 if expected else None})
    # Tail/overflow case is tested separately from ordinary short posts.
    long_text = ("آج کی بات اور روزمرہ کی زندگی کے بارے میں گفتگو۔ " * 43)[:2070]
    long_text += " میں اپنی زندگی ختم کرنے کا سوچ رہی ہوں اور مجھے مدد چاہیے۔"
    started = time.perf_counter()
    overflow = moderate(ModerationRequest(text=long_text))
    overflow_seconds = time.perf_counter() - started
    summary = {}
    for language in ("en", "ur", "roman_ur"):
        rows = [row for row in results if row["language"] == language and row["expected_topic"]]
        summary[language] = {"authored_topic_examples": len(rows),
                             "expected_topic_top3_hits": sum(row["expected_in_top3"] for row in rows),
                             "expected_hint_at_fixed_0_5": sum(row["expected_hint_at_0_5"] for row in rows)}
    report = {**metadata(), "fixture_provenance": source["provenance"],
              "not_independent_validation": True, "fine_tuned": False,
              "no_patient_data": True, "load_seconds": round(load_seconds, 4),
              "warm_p50_seconds": round(float(np.percentile([row["seconds"] for row in results], 50)), 4),
              "warm_p95_seconds": round(float(np.percentile([row["seconds"] for row in results], 95)), 4),
              "summary": summary, "cases": results,
              "overflow": {"characters": len(long_text), "seconds": round(overflow_seconds, 4),
                           "scores": overflow["scores"], "full_text_processed": overflow["full_text_processed"]}}
    destination = ROOT / "artifacts/community/minilm_v1/engineering_smoke.json"
    destination.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("model_version", "load_seconds", "warm_p50_seconds",
                                                "warm_p95_seconds", "summary", "overflow")}))
    print("Authored regression hints only; not moderation/clinical accuracy. No server started.")


if __name__ == "__main__":
    main()
