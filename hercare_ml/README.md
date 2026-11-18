# HerCare M4 model service

This directory contains the isolated Python inference service and reproducible
training code for M4. Raw datasets and experimental artifacts are ignored by
Git. The reviewed baseline artifact and its metadata are versioned so a clean
deployment is reproducible without downloading health data at image-build time.

The public PERI_DEP record is cross-sectional. Its `Labelling` field describes
the current PHQ-9-derived state and is not a future outcome. Consequently:

- The legacy `training.train --task baseline` reproduces the checked-in artifact;
  its feature meanings and row split have known limitations documented in the audit.
- Legacy `--task trajectory` is disabled, including direct calls, because its
  row-random path could bypass prospective provenance and horizon checks. Use
  `training.forecast_train` with verified dated follow-ups and participant groups.
- A future scope alone is not sufficient for automated ML escalation: the
  Node service also requires `validation_status=externally_validated_and_approved`.
  The present runtime labels all available artifacts `research_only`, so no
  probability-based automatic guardian alert is enabled. Independent screening
  safety-item and explicit danger-rule handling remain in place.

For new PERI_DEP experiments, use the curated extraction/training recipe:

```powershell
.venv\Scripts\python -m training.curated_train --input data\raw\peri_dep_dataset.csv --output-dir artifacts\experiments\new_run_name
```

This selects exact source fields, removes repeated full source records, validates
labels, isolates repeated selected-feature patterns across partitions, fits
imputation only on training data, and balances training class weights. It compares
six source measurements with the three measurements that directly match app
inputs. Output includes selected CSV, processed matrices, audits and calibrated
research artifacts. Existing results are never overwritten. These artifacts use
`research_pipeline` and are deliberately incompatible with the live inference
loader; do not promote them without validation and a reviewed feature contract.
See `../ML_CURATED_TRAINING_REPORT.md` for the actual results and missing recovery data.

Research source/feature extraction (does not replace the deployed model):

```powershell
.venv\Scripts\python -m scripts.download_research_data
.venv\Scripts\python -m training.research_features --source bangladesh_ppd_v3 --input data\raw\bangladesh_ppd_v3\PPD_dataset_v3.csv --output-dir data\processed\new_bangladesh_run
.venv\Scripts\python -m scripts.export_research_catalog --output-dir data\processed\new_evidence_run
```

`research/source_catalog.json` distinguishes public, restricted and unverified
participant data for the 25 reviewed references. Published aggregate estimates
are evidence, not patient rows. Source-specific adapters preserve field meanings,
keep labels separate, audit arithmetic/category inconsistencies and leave null
predictors for training-only preprocessing. Research output directories are
ignored and must be new; no previous export is overwritten. The PeerJ supplement
download currently fails file-type validation when its link returns HTML.

`training.longitudinal_features` supports de-identified, consented, dated HerCare
exports with real earlier observations and actual later outcomes. It rejects
declared synthetic inputs and private content, checks availability timestamps,
separately gates usage/notification measurements by permission, and calculates
calendar-based 1/7/14/30-day features. No prospective source export was obtained
in this task; this is tested extraction infrastructure, not a trained recovery
model. See `../RESEARCH_EXTRACTION_REPORT.md` for schemas, outputs and limitations.

Setup and local verification:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
.venv\Scripts\python -m pytest
.venv\Scripts\python -m uvicorn app.main:app --host 127.0.0.1 --port 8001
```

## October 2026 workflow update

See [the implementation report](../ML_WORKFLOW_IMPLEMENTATION_REPORT.md)
for the scope mapping, measured results, consent safeguards and deployment limits.
The checked-in baseline weights are unchanged; the input mappings now preserve
the actual source meanings rather than substituting income or support identity.
The API exposes no fabricated clinical confidence.

Private authenticated endpoints now include `/v1/recovery` (descriptive change)
and `/v1/text/sentiment` (public-corpus sentiment, not clinical distress).
Provision the small CPU sentiment models before deploying that optional feature:

```powershell
.venv\Scripts\python -m scripts.download_sentiment_sources
.venv\Scripts\python -m training.sentiment_train --input-dir data\raw\sentiment --output-dir artifacts\sentiment\new_public_run
```

Training requires a new output directory. Set `SENTIMENT_MODEL_DIR` to that trusted
directory for a non-Docker service. The Dockerfile copies the operator-provisioned
`artifacts/sentiment/public_v2` directory, including the already trained local v2
models. A clean checkout contains only `.gitkeep`; provision the three models
from a reviewed training run before building an NLP-enabled image. Do not copy
private raw data or load externally supplied untrusted joblib files. Missing
models cause rule fallback; they do not block journal/chat saves. No Docker
image or deployed service was launched as part of this task.

Research collection and export are disabled by default, and remain disabled
in the actual local configuration. Do not enable them without an approved study,
separate participant consent and managed pseudonymization keys. The reviewed
public-data-only training runs do not use hospital or existing app-user records.

`training.event_features` converts a schema-2 authorized source-event export into
availability-aware weekly indices and real follow-up labels.
`training.forecast_train` now compares regularized logistic classification,
constrained random forests and small gradient-boosted trees using full nested
participant-grouped cross-validation (5 outer/3 inner by default). Training-only
calibration participants remain separate. It supports instrument-specific
incident future screen positivity and symptomatic future score worsening at
day 14 +/- 3, not score guessing or diagnosed depression onset. Exact versions,
languages, explicit research cutoffs, fresh compatible baselines, real later
outcomes and checksummed source-export tables are required. The other instrument
is an optional predictor only with its own explicit version/language and
freshness checks. No synthetic data or automatic promotion is enabled.

After an approved, authorized study provides actual follow-ups, extract and
train in new directories. These commands are documentation, not work performed
on private app records in this implementation:

```powershell
.venv\Scripts\python -m training.event_features --input approved_source_export.json --output-dir data\processed\new_followup_run
.venv\Scripts\python -m training.forecast_train --input-dir data\processed\new_followup_run --output-dir artifacts\experiments\new_incident_run --instrument phq9 --instrument-version-language phq9-v1:en --screen-positive-cutoff 10 --task incident_screen_positive
```

The version and cutoff above are illustrative declared research settings, not
a clinical policy recommendation; use the study's reviewed exact definitions.
For symptomatic score-increase research use `--task future_worsening` with an
explicit `--minimum-change-points`. A negative worsening label means not
worsening, not remission. See `../DEPRESSION_FORECAST_AND_MONITORING.md` for
the target definitions, data gaps and clinical promotion gates. No genuine
follow-up model is trained here. The 30-participant/100-row floor is a pilot
guard, not a power calculation; group/class/calibration checks may require more.

The mother-only `/v1/recovery` response adds `depression_monitoring`: separate
fresh EPDS/PHQ-9 trends, supporting mood/sleep observations, safety history and
an explicitly untrained/null future outlook. Bedtime/wake statistics are
circular (midnight wrap), not arithmetic clock means. Migration 017 adds only
future consented research sleep-clock snapshots; it was applied locally through
the normal migration runner on 2026-10-11 alongside M10 migration 018. Apply all
pending migrations normally in other deployment environments. Research remains
disabled and old snapshots are
not backfilled. Normal care summaries use existing sleep records immediately
after the updated code is deployed; research participation is not required.

Production must set `ENVIRONMENT=production`, `MODEL_PATH`, and a strong
`ML_SERVICE_TOKEN`. Keep this service on a private network behind the Node API;
mobile clients must never call it directly.

## M4 synthetic forecast experiment

Run from `hercare_ml` with its Python dependencies installed.

```powershell
.venv\Scripts\python -m training.synthetic_m4 --output-dir artifacts\experiments\new_m4_synthetic_run --seed 42 --participants 600
```

The command generates all records in memory and writes separate synthetic
feature, outcome, and partition CSVs, a JSON report, and an isolated model
artifact. It uses three prediction windows per simulated mother and separates
whole mothers across fitting, interval calibration, and testing. The second
test cohort weakens the simulated links and increases outcome noise. Use a new
output directory for each run.

The experiment compares carrying the latest EPDS score forward, EPDS-only
ridge regression, and ridge and gradient boosting with the full synthetic
feature set. A single predicted EPDS score yields four severity bands, new
screen positivity among mothers below the research cutoff at baseline, and
symptom direction under a four-point change rule. The report includes score
error, interval coverage, confusion matrices, per-class recall, and incident
AUROC. It also reports a synthetic probability calibration and the sensitivity
and false-alarm rate for a threshold chosen using only calibration participants.
These metrics measure the assumptions in the generator. Real-world
accuracy requires independent dated postpartum follow-ups. The live service
requires a different artifact contract and the real follow-up trainer
requires real consented source events.

## Hum-Raaz M6 support service

The dedicated private `/v1/chatbot/reply` endpoint now supports three-language
source-card dialogue, bounded private history and separately consented aggregate
context. It is distinct from M7 guardian messaging. See the
[implementation/model card](C:/Users/WSPL/Downloads/HerCare/HUM_RAAZ_IMPLEMENTATION_AND_MODEL_CARD.md)
and [research review](C:/Users/WSPL/Downloads/HerCare/CHATBOT_RESEARCH_AND_PUBLICATION_REVIEW.md).

The custom retrieval ranker/index was trained on original engineering examples,
not patient records. The local Qwen model is pretrained and tested, not fine-tuned;
it can select only a known evidence ID or abstain, not write arbitrary medical
advice. Retrieval support remains available if the optional model process is off.
Default `CHATBOT_GENERATION_ENABLED=false` remains a deliberate operational
boundary, not a declaration of clinical readiness. Since M10 (2026-10-11),
eligible rule-based guardian alerts require the mother's separate, default-off
safe-recipient confirmation for the current link; Tier2/model flags alone are
insufficient. The old `CHATBOT_GUARDIAN_ALERTS_ENABLED` prototype gate is obsolete.

Reproduce the private-data-free retrieval comparison using a fresh directory:

```powershell
.venv\Scripts\python -m training.chatbot_train --output-dir artifacts\experiments\new_chatbot_run
.venv\Scripts\python -m scripts.chatbot_download
.venv\Scripts\python -X utf8 -m scripts.chatbot_smoke --output-dir artifacts\experiments\new_chatbot_smoke
```

The provisioning script downloads about 2.5GB of ignored, checksum-pinned server
weights plus a Windows CPU runtime. It starts no service. Reviewed retrieval
weights belong in `artifacts/chatbot/retrieval_v1/retrieval.joblib` or the operator's
`CHATBOT_RETRIEVER_PATH`. The Dockerfile includes the knowledge and provisioned
retrieval directory; it intentionally does not contain the Windows runtime or
large model weights. Linux/same-network-namespace model-process deployment is
described in the model card. No external AI provider key is required, but a strong
internal service token and stable conversation encryption keys remain mandatory.

Do not run legacy baseline training over the preserved checked-in weights.
Use curated research experiments for comparison and do not promote them without
external validation. Prospective research export remains off; saving a bot
conversation is never permission to use it as training data.
# M5 private voice transcripts (2026-10-11)

The same owned ML server now exposes authenticated POST /v1/audio/transcribe.
Install requirements-voice.txt and provision the public model using
python scripts/voice_download.py. Weights stay server-side under
artifacts/voice/small, outside Git/the mobile app. Docker installs pinned audio
dependencies but requires a separately provisioned read-only model mount.
See [M5 implementation/deployment](../M5_VOICE_IMPLEMENTATION_AND_DEPLOYMENT.md)
and voice.env.example. No Google Speech service/external provider key is used.
Internal service authentication and server compute remain required. ASR output
is a human-reviewed draft, not verified safety or clinical evidence.

## M9 public offline meditation assets (2026-10-12)

`scripts/meditation_audio.py` is an explicit build-time asset generator, not an
inference route. It reads the original Flutter English/Urdu caption catalog and
writes 24small monoAAC/M4Aclips plus text/audio SHA256 provenance. The shipped
clips work without a network, speech API, or TTS engine on the phone/server.
`--verify` checks every audio decode/hash without synthesis or speaker playback.
Only asset regeneration needs `requirements-meditation-assets.txt`; do not add
the GPL speech engine to the phone or normal server image. Synthetic speech and
unreviewed Urdu pronunciation are disclosed. See
[M9 implementation/deployment](../M9_IMPLEMENTATION_AND_DEPLOYMENT.md).
