"""Export reviewed study evidence and candidate feature provenance, never patients."""

import argparse
import csv
import json
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[1] / "research" / "source_catalog.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.output_dir.exists():
        raise FileExistsError("Choose a new output directory")
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    for filename, fields, rows in [
        ("study_sources.csv", ["id", "study", "url", "raw_status", "extracted", "use"],
         [{k: s[k] for k in ["id", "study", "url", "raw_status", "extracted", "use"]} for s in catalog["sources"]]),
        ("candidate_feature_evidence.csv", ["feature", "source_ref", "source_url", "participant_rows_extracted", "data_kind"],
         [{"feature": f, "source_ref": s["id"], "source_url": s["url"],
           "participant_rows_extracted": s["extracted"], "data_kind": catalog["data_kind"]}
          for s in catalog["sources"] for f in s["candidate_features"]]),
    ]:
        with (args.output_dir / filename).open("x", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
    print(f"Exported {len(catalog['sources'])} source records; these are not participant training rows")


if __name__ == "__main__":
    main()
