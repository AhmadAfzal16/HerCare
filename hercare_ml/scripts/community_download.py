"""Provision public MIT multilingual triage weights; no app/server or patient data.

The revision and large-file checksums are pinned. Downloads stay under ignored
artifacts/community. No executable/pickle/custom Python weights are accepted.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys

os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.community_moderation import REPOSITORY, REVISION, MODEL_VERSION, checksum, verified_files

FILES = {
    "onnx/model.onnx": (428127016, "79f8cda2b1230585a95ea0514a6f1bd21c5c986ba0529bb3261213a3e195fa6e"),
    "onnx/tokenizer.json": (17082854, "b2116c05e7305eea30394284760789681c5b3440dd4cd9a8c77539da68f9e8a6"),
    "onnx/config.json": (921, None),
    "README.md": (6741, None),
}


def provision(destination: Path):
    from huggingface_hub import hf_hub_download
    destination = destination.resolve()
    if (destination / "manifest.json").is_file():
        verified_files(destination)
        print("Existing pinned community model verified; no overwrite.", flush=True)
        return
    destination.mkdir(parents=True, exist_ok=True)
    digests = {}
    for name, (size, expected) in FILES.items():
        print("Provisioning " + name + " (" + str(size) + " bytes)", flush=True)
        existing = destination / name
        if existing.is_file() and (existing.stat().st_size != size or (expected and checksum(existing) != expected)):
            raise ValueError("Existing model file differs; inspect it before replacing: " + name)
        path = Path(hf_hub_download(REPOSITORY, name, revision=REVISION,
                                   local_dir=str(destination), token=False))
        digest = checksum(path)
        if path.stat().st_size != size or (expected and digest != expected):
            raise ValueError("Public model size/checksum mismatch: " + name)
        digests[name] = digest
    manifest = {"repository": REPOSITORY, "revision": REVISION, "license": "MIT",
                "runtime": "onnx-cpu", "model_version": MODEL_VERSION, "sha256": digests,
                "source": "https://huggingface.co/" + REPOSITORY,
                "clinical_validation": False, "hercare_fine_tuned": False,
                "usage": "private triage hints, mandatory human approval, no clinical probability"}
    with (destination / "manifest.json").open("x", encoding="utf-8") as target:
        json.dump(manifest, target, indent=2)
        target.write("\n")
    verified_files(destination)
    print(json.dumps({"model_version": MODEL_VERSION,
                      "bytes": sum(size for size, _ in FILES.values()), "server_started": False}), flush=True)


if __name__ == "__main__":
    provision(Path(__file__).resolve().parents[1] / "artifacts" / "community" / "minilm_v1")
