"""Provision public MIT-licensed ASR weights; never reads patient data or starts a server."""
from __future__ import annotations
import hashlib
import json
import pathlib
from huggingface_hub import HfApi, snapshot_download

REPOSITORY = "Systran/faster-whisper-small"
FILES = ("model.bin", "config.json", "tokenizer.json", "vocabulary.txt", "preprocessor_config.json")

def main():
    destination = pathlib.Path(__file__).parents[1] / "artifacts" / "voice" / "small"
    manifest_path = destination / "manifest.json"
    existing = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else None
    info = HfApi().model_info(REPOSITORY, revision=existing["revision"] if existing else None,
                             files_metadata=True, token=False)
    if not info.sha or len(info.sha) != 40:
        raise RuntimeError("Model revision is unavailable")
    snapshot_download(REPOSITORY, revision=info.sha, local_dir=str(destination),
                      allow_patterns=list(FILES), token=False)
    digests = {}
    for name in FILES:
        path = destination / name
        if not path.is_file():
            if name == "preprocessor_config.json": continue
            raise RuntimeError("Required public model file is missing: " + name)
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        digests[name] = digest.hexdigest()
        remote = next(file for file in info.siblings if file.rfilename == name)
        if remote.lfs and remote.lfs.sha256 != digests[name]:
            raise RuntimeError("Public weight checksum mismatch")
    manifest = {"repository": REPOSITORY, "revision": info.sha, "license": "MIT",
                "sha256": digests, "usage": "server-only ASR draft, human review required",
                "source": "https://huggingface.co/Systran/faster-whisper-small"}
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"repository": REPOSITORY, "revision": info.sha,
                      "bytes": sum((destination / name).stat().st_size for name in digests)}))

if __name__ == "__main__":
    main()
