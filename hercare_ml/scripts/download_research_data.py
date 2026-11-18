"""Fetch only explicitly listed, publicly licensed research files, with provenance.

Run from hercare_ml: python -m scripts.download_research_data
Existing files are never overwritten; checksum/size errors fail closed.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1] / "data" / "raw"
FILES = [
    {
        "source_id": "bangladesh_ppd_v3", "filename": "PPD_dataset_v3.csv",
        "url": "https://data.mendeley.com/public-files/datasets/4nznnrk8cg/files/26c702d7-7cba-42f0-898f-ca7261f61955/file_downloaded",
        "sha256": "451d6ed3c41ca4b5da235df5086913604ee0b700f0914f792ef7c5af54a4724a",
        "bytes": 483135, "citation": "https://doi.org/10.17632/4nznnrk8cg.3",
        "license": "CC-BY-4.0",
    },
    {
        "source_id": "bangladesh_ppd_v3", "filename": "PPD_Data_Dictionary_v3.csv",
        "url": "https://data.mendeley.com/public-files/datasets/4nznnrk8cg/files/1edfebe9-cc50-4819-8046-d13b2f49338d/file_downloaded",
        "sha256": "2a5c55df53135ca69b707a001c0d1f9a977d70bffdf74d468011043a6aaf0ac6",
        "bytes": 14983, "citation": "https://doi.org/10.17632/4nznnrk8cg.3",
        "license": "CC-BY-4.0",
    },
    {
        "source_id": "sajjad_peerj_2024", "filename": "peerj-12-17711-s001.xlsx",
        "url": "https://pmc.ncbi.nlm.nih.gov/articles/instance/11260416/bin/peerj-12-17711-s001.xlsx",
        "sha256": None, "bytes": None,
        "citation": "https://doi.org/10.7717/peerj.17711/supp-1",
        "license": "CC-BY-4.0",
    },
]
MAX_BYTES = 10 * 1024 * 1024


def verify(payload: bytes, entry: dict) -> str:
    digest = hashlib.sha256(payload).hexdigest()
    if not payload or len(payload) > MAX_BYTES:
        raise ValueError("Empty or oversized research file")
    if entry["bytes"] is not None and len(payload) != entry["bytes"]:
        raise ValueError(f"Unexpected byte count for {entry['filename']}")
    if entry["sha256"] is not None and digest != entry["sha256"]:
        raise ValueError(f"Checksum mismatch for {entry['filename']}")
    if entry["filename"].endswith(".xlsx") and not payload.startswith(b"PK"):
        raise ValueError("Repository returned something other than an XLSX file")
    return digest


def main() -> None:
    failures = []
    for entry in FILES:
        destination = ROOT / entry["source_id"] / entry["filename"]
        try:
            if destination.exists():
                payload = destination.read_bytes()
                resolved_url = entry["url"]
            else:
                request = urllib.request.Request(entry["url"], headers={"User-Agent": "HerCare-research/1.0"})
                with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 - fixed public URLs
                    payload = response.read(MAX_BYTES + 1)
                    resolved_url = response.url
            digest = verify(payload, entry)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if not destination.exists():
                with destination.open("xb") as stream:
                    stream.write(payload)
            metadata = destination.with_suffix(destination.suffix + ".provenance.json")
            if not metadata.exists():
                with metadata.open("x", encoding="utf-8") as stream:
                    json.dump({**entry, "actual_sha256": digest, "actual_bytes": len(payload),
                               "verified_at_utc": datetime.now(timezone.utc).isoformat(),
                               "resolved_url": resolved_url, "data_kind": "public_research_source"},
                              stream, indent=2)
            print(f"Verified {entry['source_id']}/{entry['filename']}: {len(payload)} bytes, sha256={digest}")
        except (OSError, ValueError) as error:
            failures.append(entry["source_id"])
            print(f"Unavailable {entry['source_id']}/{entry['filename']}: {error}")
    if failures:
        raise SystemExit("Some public files were unavailable; successful files were preserved.")


if __name__ == "__main__":
    main()
