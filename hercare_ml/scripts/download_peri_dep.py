"""Download the exact CC BY 4.0 PERI_DEP source used by HerCare M4."""

from __future__ import annotations

import hashlib
import pathlib
import urllib.request

URL = "https://zenodo.org/api/records/11403247/files/dataset.csv/content"
EXPECTED_SHA256 = "3d2efa3aaea9e4ba3a404c6dbbd4a82a4c832c7cd578de10ff2ae28967062c42"
DESTINATION = pathlib.Path(__file__).parents[1] / "data" / "raw" / "peri_dep_dataset.csv"


def main() -> None:
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    temporary = DESTINATION.with_suffix(".download")
    urllib.request.urlretrieve(URL, temporary)  # noqa: S310 - fixed trusted URL
    digest = hashlib.sha256(temporary.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"PERI_DEP checksum mismatch: {digest}")
    temporary.replace(DESTINATION)
    print(f"Verified PERI_DEP dataset: {DESTINATION}")


if __name__ == "__main__":
    main()

