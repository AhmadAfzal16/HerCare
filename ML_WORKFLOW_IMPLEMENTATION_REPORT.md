# HerCare: first three ML workflow tasks

Date: 2026-10-08. Implementation and automated verification, not a clinical validation report.

## Outcome

| Requested area | Implemented | Actual status |
| --- | --- | --- |
| Correct prediction inputs and safe data workflow | Exact optional model context, missing-data/permission handling, explicit research-only predictions, consent/export safeguards, timestamp-aware extraction and follow-up training recipe | Integrated and tested. Real-patient research gathering/export remain off. No genuine 14-day forecast has been trained. |
| Personal recovery tracking | Private Python endpoint, mother-authorized Node endpoint and responsive Risk Insights panel for daily/weekly/fortnightly/monthly comparisons | Integrated and tested. Descriptive recorded change, not clinical recovery or proof of treatment efficacy. |
| Multilingual sentiment and review | Three public-corpus CPU models, private inference, journal/chat integration, bounded timeout/fallback, independent safety rules, 240-item review queue | Models actually trained and exercised. Human review is pending; clinical distress is not trained or validated. |

The app was not installed or launched on a device, and persistent services were not restarted. Migration `015_ml_research.sql` was applied to the local database. Test fixtures were rolled back; no real account was opted into research or exported.

## 1. Scope and data gathering

The scope requests M4 prediction from demographics, EPDS/mood and sleep/device signals; M5 journal/mood analysis; multilingual emotional analysis; and dated recovery monitoring. These are different targets, not one interchangeable depression formula.

Your permission is public research datasets only for current training. No hospital authorization was provided. Therefore:

- Existing app records were not harvested for model training.
- Real-user research collection/export remain disabled; normal care features do not depend on research participation.
- Paper statistics and formulas are evidence, not fabricated patient records. Restricted/unavailable participant datasets were not silently replaced with synthetic observations.
- A real future outcome requires an actual later assessment. Current PHQ-9 labels cannot be renamed “depression in two weeks.”

Public-source availability for the previously reviewed 25 references remains documented in `hercare_ml/research/source_catalog.json` and `RESEARCH_EXTRACTION_REPORT.md`. Not every paper releases participant-level data; no claim is made that all research papers have been extracted.

### Depression research data and exact parameters

PERI_DEP has 14,008 source rows and 7,008 after removing full repeated records. Its six source-compatible fields are age, number of children, education, household type, ability to afford basic needs, and mother-in-law relationship quality. They are not previous deliveries, income category, or the identity of a support person. The live builder now respects that distinction, with three optional questions rather than extra mandatory onboarding requirements.

The Bangladesh v3 source has 800 rows and a codebook. The extractor preserves 21 research predictors: age, pregnancy count, education category, household type, children band, newborn-age band, in-law relationship category, husband relationship category, support band, income band in BDT, pregnancy-loss category, cesarean delivery, baby sex, reported birth complication, planned pregnancy, regular prenatal checks, fear of pregnancy, reported abuse, ability to confide, prenatal PHQ-2 history and prepregnancy PHQ-2 history. These are source-specific research fields, not 21 new required app questions.

PHQ-9 items, total and category are kept out of contemporaneous predictor matrices and audited separately as outcomes. There were 88 item/total discrepancies and 40 category discrepancies (overlapping); 681 rows passed both checks. Restricting to source first-year postpartum bands leaves 413 research-training rows. The source EPDS wording differs from the standard instrument, so its labels were not used in the new classifier. This is not clinician-diagnosed depression. Source dataset/licence: [Bangladesh postpartum data v3](https://data.mendeley.com/datasets/4nznnrk8cg/3).

### Prospective infrastructure, deliberately disabled

`015_ml_research.sql`, the research API, `training/event_features.py` and `training/forecast_train.py` provide:

- Independent, versioned opt-in; no automatic opt-in or historic bulk backfill.
- Adult, active mother and basic-consent eligibility, approved server study ID, separate collection/export switches and secret HMAC pseudonyms.
- Allow-listed numeric context, mood, screening, sleep, permission-gated telemetry, activity and numeric journal-analysis/model-output snapshots. No raw journals, chats, notification content, audio, names, phone numbers or original account UUIDs in research exports.
- Administrator-only bounded export with current DB role checking, audit entries, study isolation and consent locks. Repeated opt-in is idempotent; changing study requires withdrawal first.
- Withdrawal removes research copies, not care records. Previously exported copies/backups still need controlled deletion by the research team.
- Availability-aware revisions, calendar-based 1/7/14/30-day features, weekly index dates and real follow-up around day 14 ±3. Records unavailable at an index do not leak into its predictors.
- Participant-disjoint train/calibration/test partitions; future targets, private content and synthetic training data are refused. Missing future labels are excluded, never imputed.

The schema is pseudonymous, not a guarantee of anonymity: dates and detailed attributes still require restricted research handling. Capture timestamps are server transaction timestamps, not an independently validated subdaily measurement system. Export pages must be combined consistently before longitudinal extraction; stale self-reported postpartum age and permissions require continued operational review.

## 2. Missing values, balancing and training

Original source files and hashes are preserved. Invalid codes become unknown; no guessed obstetric diagnosis, sleep-from-screen-off, support-quality-from-person-identity, or healthy value is inserted.

Numeric imputation uses training-partition medians with missingness indicators. Categorical nulls use an explicit missing category and unknown-safe one-hot encoding. Scaling/encoding are fitted only on training data. The original raw extracted tables retain their nulls; preprocessing does not overwrite them.

Class imbalance is handled with balanced training weights, not by inventing mothers or oversampling before splitting. Calibration has a separate held-out partition; test labels are not used for fitting. Exact selected-feature groups are kept apart for cross-sectional sources without verified person IDs, but this is only a conservative identity proxy. Prospective data use actual pseudonymous participant groups. Site/temporal external validation is still required.

### Measured Bangladesh experiment

247 training, 83 calibration and 83 test rows; 231 positive and 182 negative source screens overall. Compared regularized logistic regression and gradient boosting with a fixed 0.5 evaluation threshold.

| Research configuration | Test accuracy | ROC-AUC | Balanced accuracy |
| --- | ---: | ---: | ---: |
| 21-source-context logistic regression | 78.31% | 0.8345 | 78.43% |
| 21-source-context gradient boosting | 74.70% | 0.8322 | 74.91% |
| Four-shared-context logistic regression | 49.40% | 0.2997 | 50.00% |
| Four-shared-context gradient boosting | 48.19% | 0.3400 | 48.78% |

The four shared fields are age, household type, cesarean delivery and baby sex. Source education, income, support and child bands do not equal the live contract. The good fuller-source result does not establish useful performance from the current app's comparable inputs. No experiment was promoted or pooled indiscriminately with PERI_DEP.

Results: [Bangladesh report](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/bangladesh_firstyear_20261008/report.json). Prior curated PERI_DEP results remain in [the curated training report](C:/Users/WSPL/Downloads/HerCare/ML_CURATED_TRAINING_REPORT.md); they were weak and are not hidden by the stronger Bangladesh figure.

The original deployed ensemble weights are unchanged. Their recorded 66.42% accuracy, 52.70% balanced accuracy and 0.6231 AUC are historical internal metrics with split/feature limitations, not a current production accuracy guarantee. Correcting the runtime feature meanings does not retroactively validate those old results. Numeric “clinical confidence” derived from completeness was removed; contributions are labelled observed context, not model attribution. Probability-based automatic guardian escalation is blocked without explicit externally validated/approved metadata. Existing screening safety-item and danger-language handling are independent and remain in place.

No genuine future model was trained: the available depression datasets are cross-sectional. The future trainer compares logistic regression/gradient boosting only after actual dated follow-ups exist and rejects the wrong outcome horizon. Its 30-participant/100-follow-up-row minimum is a pilot guard, not an adequate clinical sample-size justification. Genuine public longitudinal data still need an approved source-specific adapter and population/instrument harmonization.

## 3. Recovery calculation and UI

Implemented `app/recovery.py`, `/v1/recovery`, mother-authorized `/api/v1/risk/recovery`, and `recovery_panel.dart` in Risk Insights. The Node-to-Python request carries bounded aggregate observations, not account IDs or raw private text.

The panel compares adjacent 1/7/14/30-day windows. Ratings are 1–5, normalized onto a 0–100 descriptive index. Initial design weights are mood 0.4, energy 0.2, sleep quality 0.2 and perceived support 0.2. Only comparable observed fields are retained in both windows, weights are renormalized, and at least 70% complete-day coverage per window is required. These weights/coverage rules are research design choices, not validated medical coefficients.

`relative change (%) = 100 × (current recorded index − previous recorded index) / previous recorded index`.

A previous index of 50 and current index of 51 is **2% relative recorded-index increase**, not proof the mother's depression improved by 2%. A zero baseline returns percentage unavailable and absolute point change instead. Sparse data show “insufficient data,” not an optimistic estimate. Percentages are not capped; changing comparable fields can limit comparisons across successive reports.

EPDS/PHQ-9 changes stay separate: same instrument, version and language only, actual assessment dates/gaps shown, and mixed-direction signals flagged. The comparator finds the closest earlier assessment to the intended 7/14-day cadence; it does not claim irregular gaps are exact follow-ups. Reliable Change Index is not enabled without an appropriate documented reliability/SD reference. Safety-item positives cannot be cancelled by an improving wellbeing index.

The new panel supports English/Urdu through the existing language system, wrap-safe labels, scrolling and optional model context. Small-screen layout tests pass; this does not guarantee every device/accessibility setting is overflow-free.

## 4. Multilingual sentiment: actual trained data/models

Public downloads record licence, citation, pinned source URL, SHA-256 and byte size:

- [UCI Sentiment Labelled Sentences](https://archive.ics.uci.edu/dataset/331/sentiment+labelled+sentences): CC BY 4.0, positive/negative review sentences; no neutral class or clinical labels.
- [UCI Roman Urdu](https://archive.ics.uci.edu/dataset/458/roman+urdu+data+set): CC BY 4.0, general positive/negative/neutral comments.
- [Urdu MultiDomainClassification](https://huggingface.co/datasets/umar178/UrduMultiDomainClassification): uploader-declared CC0-1.0, pinned revision `da5a04db5f68457204b3ced9caa457a26bbd9d48`. Annotation provenance/methodology is insufficiently documented; independent review is required. No claim of clinically reviewed or necessarily naturalistic examples.

Cleanup: 58,050 parsed/raw entries, 331 invalid/missing-label/text/licence entries, 1,702 conflicting-label entries, 7,517 duplicate normalized texts removed; **48,500 retained**. Missing sentiment labels are never guessed. NFKC/case/whitespace normalization and normalized-text group isolation prevent exact duplicate contamination, but do not establish independent authors or remove all near-duplicate/template leakage.

Each language model uses character 3–5-gram TF-IDF (maximum 40,000 features), balanced logistic regression, and separate sigmoid calibration. It runs on CPU without a paid language-model API or GPU. General-domain test results:

| Language | Curated rows | Test rows | Accuracy | Macro-F1 |
| --- | ---: | ---: | ---: | ---: |
| English | 2,979 | 596 | 82.72% | 0.8269 |
| Roman Urdu | 19,472 | 3,895 | 65.49% | 0.6408 |
| Urdu | 26,049 | 5,210 | 89.96% | 0.8996 |

Results: [sentiment report](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/sentiment/public_v2/report.json). These are general-corpus benchmark results, not accuracy on postpartum mothers' journals/chats, and not depression/suicide probabilities.

The private endpoint caches the three trusted models, limits concurrent work, and abstains below 0.6 probability or 20% known character-feature coverage. These thresholds are operational heuristics, not validated clinical cutoffs. Language routing is script/word-based and can be wrong for short or mixed-language text. The Node adapter has a 1.5-second timeout, limited concurrency and failure cooldown; journal/chat saving falls back to existing rules if models are missing, busy, uncertain or unreachable.

The model supplies sentiment only. Explicit danger rules run first and are never downgraded by a positive sentiment estimate. Rule-based distress is still a heuristic, not a validated clinical distress model. Raw text is processed privately for inference but is not logged/cached or included in research exports. Notification previews remain analyzed on-device by existing rules. New encrypted voice recordings are not transcribed; only the existing configured legacy transcription path can receive text NLP.

### Public annotation/review workflow

Created 240 public examples in `data/processed/sentiment_review/public_review.jsonl`, stratified by language and sentiment. No user text was harvested. `scripts/sentiment_review.py` requires two distinct reviewer IDs and complete agreement; incomplete/disagreed rows remain pending and are not accepted training labels. This enforces distinct IDs, not independently verified reviewer qualifications.

For review: sentiment means the expressed tone (positive/negative/neutral); do not infer an author's diagnosis. Distress labels are `not_labelled`, `none`, `possible`, `high` and require an agreed clinician-supervised rubric before medical interpretation. Reviewers should annotate independently, record reviewer identity/qualification securely outside the public artifact, and resolve disagreements with a qualified adjudicator. A completed consensus export still has `clinical_validation=false`.

**No human reviews completed and no clinical distress classifier trained.** A postpartum multilingual external evaluation, label-quality audit and failure analysis are outstanding. Publishing should disclose source provenance, domain mismatch, proxy grouping, template leakage risk and the unreleased human-review status.

## 5. Verification and deployment handoff

- Python tests: **71 passed** after adding forecast horizon/data-type guards; source compilation also checked earlier.
- Backend default suite: **53 passed, 7 opt-in integration tests skipped**, no failures. The focused PostgreSQL ML research/recovery integration test passed separately with rollback fixtures and a mocked private-ML response.
- Flutter full suite: **82 passed**, including new recovery layouts and existing module regression/layout tests. Changed Flutter files passed static analysis; changed backend modules/tests passed ESLint.
- Actual baseline artifact and metadata hashes stayed unchanged: `BE4B72F12CD4FE13BCF0222F730B3E6672A1AD5DBCB172914A0650AD037DD772` and `D13B81B6D2BC8D9FD0EB5C2018A08A9514D8D95071A01629845289F549354781`.
- Integration tests do not prove real guardian push delivery, deployed network behavior, clinical efficacy, or all-device layout behavior. No app/device launch or deployed end-to-end test was performed.

To deploy this change later: run migrations through 015 on the target DB; rebuild the Flutter app; deploy the updated Node/Python services with matching strong ML tokens over a private authenticated network. Provision the three trusted sentiment artifacts in the container/service, not raw datasets. The Dockerfile now copies the provisioned `public_v2` model directory; no image build was tested here. A clean Git checkout contains only that directory's `.gitkeep`, so provision weights before building an NLP-enabled deployment; otherwise rule fallback remains active. Hosting/storage/CPU still have infrastructure costs even though the model inference uses no paid AI API.

Leave `RESEARCH_COLLECTION_ENABLED=false` and `RESEARCH_EXPORT_ENABLED=false`. An approved protocol, lawful participant consent, source licences, key management, retention/deletion procedures and external clinical evaluation are prerequisites to any later prospective study or clinical model promotion.
