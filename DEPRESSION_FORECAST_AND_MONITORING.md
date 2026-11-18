# Depression future risk and observed progress

Implementation date: 2026-10-09. This supersedes descriptions of the original PERI_DEP classifier as a future depression forecast. It does not supersede the source data or historical experiment results.

The current report implementation, weights, questionnaire, and separate synthetic forecast experiment are documented in [M4 monitoring and 14-day forecast evaluation](M4_MONITORING_AND_VALIDATION.md).

## What the system is intended to answer

| Question | Measurement or model | Meaning |
| --- | --- | --- |
| Are reported symptoms lower or higher than before? | Compare actual dated EPDS results with EPDS, and PHQ-9 with PHQ-9 | Observed symptom change, not a diagnosis, remission, or proof of treatment benefit |
| Are supporting daily patterns changing? | Separate mood and sleep summaries over 1/7/14/30-day windows | Recorded patterns with coverage and freshness, not an interchangeable depression score |
| Might someone currently below a screening cutoff become screening-positive later? | Instrument-specific incident-positive classification at an actual day-14 follow-up | Research surrogate for elevated depressive symptoms, not clinician-confirmed onset |
| Might recorded symptoms rise further in someone already screening-positive? | Separate future-worsening classification using actual later results | Research score-direction outcome; “not worsening” does not mean recovery |

EPDS and PHQ-9 totals are not added together or converted into a supposedly validated fused probability. A completed questionnaire is scored by its instrument rules, not guessed by ML. A model estimating a *later* outcome may legitimately use an earlier questionnaire score; it must not see the later score, items, or any records not yet available at its prediction time.

The new future models are **not trained or deployed on real longitudinal data**. The mobile future-outlook section must therefore show unavailable with a null probability. The original research baseline remains separate and cannot populate that section.

## Inputs and the minimum-input approach

Normal care can use existing records without opting the mother into research. Model training is a different purpose and requires appropriate data rights and a separately approved protocol.

| Existing parameter family | Use | Important constraint |
| --- | --- | --- |
| EPDS and PHQ-9 | Earlier score, exact version/language, dates and age; later outcome in a separate table | Same instrument/version/language cohorts; missing follow-up never becomes “negative” |
| Daily mood, energy, subjective sleep quality, perceived support | Means, variability, calendar-day slopes and observed-day coverage | Null is unknown, not healthy; daily mood is not a daily PHQ-9 |
| Recorded sleep | Actual sleep duration and awakenings; recorded bedtime/wake patterns where available | Device inactivity does not prove sleep; longer sleep alone does not prove improvement |
| Optional demographic/context fields | Source-compatible age, education, household, children count, affordability and in-law relationship | Do not substitute income bands or supporter identity for different source meanings |
| Optional digital wellbeing | Permission-gated aggregate screen/late-night usage and negative-notification ratio with coverage | No raw notification text; denied permission is missing, not zero |
| Activity completion | Available in research extraction as engagement data | Completing a game or meditation is not verified therapy efficacy |

No new mandatory onboarding questionnaire is introduced. Reuse existing optional records and show insufficient data when necessary. Raw journals, chats, voice recordings and private notification content are not future-risk training features. Existing sentiment models measure general-domain tone, not depression ground truth; they are not promoted into clinical labels.

## Dataset adequacy

PERI_DEP and Bangladesh v3 contain one-time research measurements, not verified participant-linked baseline/follow-up series. PERI_DEP's deployed label is PHQ-9-derived, not EPDS. Bangladesh contains retrospective PHQ-2 histories, but those are not prospectively dated future outcomes. Its EPDS response wording also needs instrument review. Neither dataset can establish day-14 depression onset or daily recovery by adding dates or generating synthetic scores.

The previously extracted source files remain unchanged. No private app records are exported or used for training in this work. Research collection/export remain disabled. Synthetic fixtures in automated tests establish software behavior only; they are not additional mothers, a clinical training dataset, or a measured medical accuracy result.

Public longitudinal research is a possible next source, subject to access rights and a reviewed adapter. The BASIC study is prospective but its participant data require author permission and a data-transfer agreement; the paper itself is not an unrestricted patient CSV. PHQ-8 cohorts cannot silently become PHQ-9, and a six-week antenatal-to-postpartum model is not a validated 14-day postpartum app model. [BASIC study and data availability](https://www.nature.com/articles/s41598-021-86368-y), [early digital-phenotyping study](https://pubmed.ncbi.nlm.nih.gov/33574229/).

## Leakage-safe workflow

1. Define the target before inspecting model results: instrument, exact version/language, explicit research screening cutoff, prediction horizon and follow-up tolerance. Keep incident-positive and future-worsening cohorts separate. Clinical operating cutoffs need qualified review; they must not be adjusted to improve reported accuracy. The EPDS literature shows a sensitivity/specificity trade-off across cutoffs. [EPDS individual-participant meta-analysis](https://pubmed.ncbi.nlm.nih.gov/33177069/).
2. Use real participant-linked observations with performed and available timestamps. Build only features known at the index. Retain source provenance and missingness. Labels come from actual later assessments within the declared window.
3. Require a fresh compatible baseline. Incident-positive training starts below the declared cutoff. Worsening training starts at or above it and uses an explicitly declared score-increase margin. A one-point increase is an exploratory numerical direction, not a reliable or clinically important change.
4. Exclude missing targets, stale/incompatible baselines and mismatched outcomes. Never impute a diagnosis or later assessment. Preserve original tables and report excluded counts.
5. Hold out whole participants in outer cross-validation. Their overlapping weekly windows must not appear in training folds. Inner participant-grouped folds choose candidate settings. Outer labels are reserved for performance estimation. [Nested CV](https://scikit-learn.org/stable/auto_examples/model_selection/plot_nested_cross_validation_iris.html), [StratifiedGroupKFold](https://scikit-learn.org/stable/modules/generated/sklearn.model_selection.StratifiedGroupKFold.html).
6. Fit numeric medians/missingness indicators, categorical missing categories/encoding and scaling only inside training folds. Compare regularized logistic classification, constrained random forests and small gradient-boosted trees. Use training weights rather than generated patient records. No SMOTE or synthetic outcome generation is enabled. Resampling before a split can contaminate the evaluation. [Imbalance leakage guidance](https://imbalanced-learn.org/stable/common_pitfalls.html).
7. Fit probability calibration using only the outer-training portion, with participant separation from the estimator-fitting portion. Keep the evaluation probability cutoff predeclared. Calibration is not clinical approval. [Probability calibration](https://scikit-learn.org/stable/modules/calibration.html).
8. Report sensitivity, specificity, positive/negative predictive value, balanced accuracy, ROC-AUC, PR measures and calibration alongside ordinary accuracy. Report participant counts and class counts, not only row counts. No 90% guarantee follows from nested CV.
9. Save research-only artifacts and reproducible reports. Do not automatically replace live weights, trigger guardian alerts, or call a screen-positive result a diagnosis. Temporal/site external validation, subgroup evaluation, clinically reviewed decision thresholds and deployment testing remain prerequisites to promotion.

The training pilot guards are software safeguards, not a clinical sample-size calculation. Their minimum does not establish sufficient power, representativeness or an adequately precise performance estimate. Full calibration/fold checks can reject even a dataset that passes a simple row-count minimum.

## Observed progress and safety

Screening trend comparisons require compatible instruments, versions and languages and expose actual gaps/freshness. Missing, changed-language/version, irregular or stale records do not become a reassuring “stable” result. Supporting sleep duration/awakenings/bedtime/wake trends remain descriptive; no new sleep diagnostic thresholds or automatic escalation rules are invented.

Sleep research supports monitoring quality and continuity, not simply treating every increase in hours as mental-health recovery. Published associations are not coefficients validated for HerCare. [Postpartum sleep-maintenance study](https://pubmed.ncbi.nlm.nih.gov/23733081/), [sleep and depressive-symptom longitudinal study](https://pubmed.ncbi.nlm.nih.gov/27492636/).

A lower EPDS/PHQ-9 total or better mood cannot cancel a recorded self-harm concern. Historical safety-positive records without a documented resolution require review, but are not themselves proof of current imminent danger. Existing safety/crisis handling stays independent of experimental models. This change does not activate new ML-based or chatbot guardian alerts.

The older recorded-wellbeing index remains explicitly experimental and descriptive. Its relative percentage is a change in that recorded index, not a percentage of depression cured. The new monitoring view foregrounds the actual separate screening and supporting signals.

## Current delivery and remaining gates

Implemented code:

- `hercare_ml/training/forecast_cohort.py`: exact target/cohort, freshness, real-follow-up, bounded predictor and source/table provenance gates.
- `hercare_ml/training/forecast_train.py`: full 5-outer/3-inner participant-grouped candidate comparison, separate training-only calibration, fixed 0.5 evaluation threshold, honest research-only artifact/report output. No model is selected from outer test scores.
- `hercare_ml/training/event_features.py` and `longitudinal_features.py`: availability-aware real observations, source revisions, actual outcome dates, clocks represented with sine/cosine, coverage/freshness and distinct sleep-record quality. Existing model-output/text-analysis events are excluded and counted, not reused as clinical ground truth.
- `hercare_ml/app/recovery.py` and `recovery_sleep.py`: separate observed screening/supporting trends and an untrained/null future outlook. Safety history cannot disappear because of same-day repeats, lower later totals or a bounded trend display.
- Private Node recovery query/response validation and post-inference mother/consent checks. Sleep comes from saved care records; normal care does not require research participation. Export date bounds now explicitly use UTC independent of DB session timezone.
- Flutter typed monitoring and narrow responsive cards in the existing Risk Insights/recovery view. English/Urdu and the existing theme are preserved; optional context remains optional.
- New migration `017_research_sleep_cycle.sql`: enriches only future already-consented sleep research snapshots with recorded local bed/wake minutes. It was tested inside a rolled-back transaction and is **not applied** to the local database. No backfill or enablement occurs. Apply through the migration runner when deploying that optional extension; never edit applied 015/016.

Verification:

- Full Python: **149 passed**, including the new nested-CV/cohort/chronology/missingness/clock/safety cases. Test fitting uses explicitly fabricated engineering fixtures, not clinical training.
- Full Flutter: **98 passed**. Focused monitoring checks cover 320px width, 200% text scaling and English/Urdu; changed-file static analysis passed. This is not an all-device guarantee.
- Default backend automated files: **65 passed, 11 opt-in checks skipped, 0 failed**. The unrelated manual `test-chat.js` was not run.
- Focused backend: **8 passed**, including actual Python/FastAPI-to-Node responses, actual PostgreSQL sleep/source-capture rollback checks, current authorization/withdrawal and UTC export checks under Auckland/Los Angeles DB timezones. These use synthetic accounts, mocked inference where appropriate, no real pushes, and roll back database changes.
- Changed backend lint and whitespace checks passed. Non-failing existing warnings concern Starlette/AnyIO, a SciPy solver option and the single-client rollback test's queued queries. The production code uses its normal pool.
- Actual current PERI_DEP and Bangladesh processed directories were passed to the new preparation gate. Both were refused as cross-sectional future-outcome training data. No models were fitted on them for this task.
- Baseline artifact and metadata SHA-256 remained `BE4B72F12CD4FE13BCF0222F730B3E6672A1AD5DBCB172914A0650AD037DD772` and `D13B81B6D2BC8D9FD0EB5C2018A08A9514D8D95071A01629845289F549354781` respectively. Research collection/export and chatbot automatic guardian-alert enable flags remain off.

Checksums protect reproducibility/tamper detection, not independently authenticated data provenance or clinical label truth. Review data rights and actual source records before using a purported real export. Pseudonymous participant IDs/dates still require restricted storage; generated research reports are not automatically public or anonymous.

No app/device or persistent model/backend service is launched. Temporary integration-test listeners are closed afterward. No real-user study consent, data export, clinical model promotion, push delivery or deployment is performed. Saved baseline weights and unrelated modules are preserved.

Unfinished evidence-dependent steps are genuine licensed longitudinal data acquisition, instrument/population harmonization, a study sample-size justification, real training, independent temporal/site evaluation and clinical review. To forecast clinician-confirmed depression rather than a later positive screen, actual qualified diagnostic outcomes are additionally required. A new formula or artificial dataset cannot supply that missing evidence.
