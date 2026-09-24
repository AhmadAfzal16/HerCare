# HerCare M4 model service

This directory contains the isolated Python inference service and reproducible
training code for M4. Raw datasets and experimental artifacts are ignored by
Git. The reviewed baseline artifact and its metadata are versioned so a clean
deployment is reproducible without downloading health data at image-build time.

The public PERI_DEP record is cross-sectional. Its `Labelling` field describes
the current PHQ-9-derived state and is not a future outcome. Consequently:

- `--task baseline` trains a leakage-resistant research baseline using only
  demographic/social fields available to HerCare.
- `--task trajectory` requires a prospective HerCare export with a genuine
  `depressed_in_14d` outcome and all fields declared in `TRAJECTORY_FEATURES`.
- Only a `two_week_trajectory` artifact may activate automated guardian or
  crisis escalation. The baseline remains clearly labelled in the API/UI.

Setup and local verification:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
.venv\Scripts\python scripts\download_peri_dep.py
.venv\Scripts\python -m training.train --task baseline --input data\raw\peri_dep_dataset.csv --output artifacts\peri_dep_baseline.joblib
.venv\Scripts\python -m pytest
.venv\Scripts\python -m uvicorn app.main:app --host 127.0.0.1 --port 8001
```

Production must set `ENVIRONMENT=production`, `MODEL_PATH`, and a strong
`ML_SERVICE_TOKEN`. Keep this service on a private network behind the Node API;
mobile clients must never call it directly.
