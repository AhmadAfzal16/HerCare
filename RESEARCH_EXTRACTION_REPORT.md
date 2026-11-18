# Research data and feature extraction

Updated 8 October 2026. The app was not launched, its database was not accessed, and the live model was not replaced.

## What has actually been extracted

**Not all participant data from all papers have been obtained.** A published paper, an aggregate table and an original participant dataset are different sources. Some authors restrict their datasets for privacy; others publish only a method or instrument. We cannot reconstruct real participants, daily observations or recovery labels from reported sample sizes, correlations or odds ratios.

The source catalogue now covers **all 25 references in the previous HerCare research report**, with candidate variables, access status, source links and whether participant rows were actually extracted. This is not an exhaustive systematic review of all depression research. Only selected relevant aggregate estimates have been transcribed, not every table in every publication.

| Source | Original file actually available | Extracted data | Important limits |
| --- | --- | --- | --- |
| PERI_DEP [original repository](https://zenodo.org/records/11403247) | Existing original CSV, 14,008 rows | 7,008 normalised full-record-deduplicated rows; six predictors | No verified participant IDs, repeated observation timestamps or future outcomes. These are source records, not proven independent participants. |
| Bangladesh [Raisa and Kaiser, version 3](https://doi.org/10.17632/4nznnrk8cg.3) | Newly downloaded 800-row, 70-column CSV and data dictionary | 800 records; 21 selected candidate predictors; separate questionnaire outcomes and audit flags | Cross-sectional; includes up to 24 months postpartum; instrument/coding problems described below. |
| Sajjad/PeerJ [article and supplement](https://doi.org/10.7717/peerj.17711) | Public NIH-hosted XLSX link located; attempted download returned HTML | **No spreadsheet data extracted** | Downloader rejected the response. Actual sheet names, columns and coding remain uninspected. Paper interviewed 1,503 EPDS-positive women; do not assume a representative positive/negative cohort. |
| Other reviewed sources | Published methods, instrument evidence and selected study statistics | Candidate-feature provenance and selected aggregate estimates | No additional participant file verified/downloaded. Several cohorts require permission. |

For example, [BASIC/Andersson](https://www.nature.com/articles/s41598-021-86368-y) requires author agreement and a data-transfer agreement; [Yousaf](https://link.springer.com/article/10.1007/s44192-025-00225-2) explicitly restricts participant data for privacy. No authors were contacted, access agreements accepted, or restricted datasets acquired.

The Bangladesh files were verified against the repository API's expected SHA-256 and size:

- Dataset: `451d6ed3c41ca4b5da235df5086913604ee0b700f0914f792ef7c5af54a4724a`, 483,135 bytes.
- Dictionary: `2a5c55df53135ca69b707a001c0d1f9a977d70bffdf74d468011043a6aaf0ac6`, 14,983 bytes.
- Attribution: Jasiya Fairiz Raisa and M Shamim Kaiser, *Data for Postpartum Depression Prediction in Bangladesh*, Mendeley Data V3, DOI 10.17632/4nznnrk8cg.3, CC BY 4.0. HerCare extraction is a transformation, not the original authors' cleaned dataset.

Version 3 supersedes the v1 repository reference used in the earlier review. Versions are not additional independent cohorts and must not be concatenated as extra people. The download manifest fixes this version and its checksums.

## Features selected and their exact meaning

PERI_DEP reuses the reviewed six-feature adapter:

`age`, `number_of_children`, `education_level`, `household_type`, `basic_needs_financial_strain`, `mother_in_law_relationship_quality`.

Bangladesh extraction selects:

| Feature group | Output predictors |
| --- | --- |
| Demographic/family context | `age`, `education_source_category`, `household_type`, `children_source_band`, `postpartum_source_band`, `income_source_bdt_band` |
| Obstetric history | `pregnancy_count`, `pregnancy_loss_source_category`, `cesarean`, `baby_female`, `reported_birth_complication`, `pregnancy_planned`, `regular_prenatal_checkups` |
| Social/context candidates | `in_law_relationship_source_category`, `husband_relationship_source_category`, `received_support_source_band`, `reported_abuse`, `can_confide`, `fear_of_pregnancy` |
| Retrospective antenatal symptom history | `prenatal_phq2_positive`, `prepregnancy_phq2_positive` |

These are **candidate research features, not 21 new mandatory questions for mothers**. Some are already collected, some are not, and some have incompatible app meanings. Validate usefulness and incremental burden before adding collection. Baby sex is contextual information about possible social pressures, not an inherent adverse health characteristic or a causal judgement about a child.

Mappings deliberately preserve distinctions:

- An income band in Bangladeshi taka does not become the app's Pakistani income band or PERI_DEP's ability-to-afford-basic-needs response.
- A university/high-school education code is not silently relabelled as Graduation/Matric.
- `More than two` children is not an exact parity of 3. Pregnancy count, living-child count and previous deliveries are different.
- The source's `High/Medium/Low` support bands are not the app's daily 1–5 support rating. Relationship with all in-laws is not specifically relationship with a mother-in-law.
- A yes/no birth-complication field cannot identify preeclampsia, hemorrhage, preterm delivery or gestational diabetes. Coarse chronic/non-chronic disease columns were excluded rather than assigning invented diagnoses.
- Prepregnancy/prenatal PHQ-2 histories are retrospectively reported in a cross-sectional survey. Their wording does not supply actual dated prenatal observations.
- Raw questionnaire answers, current totals, severity classes, self-harm items and study row numbers are **not predictors of the same screening label**. Outcomes and safety responses are exported separately.

All 800 Bangladesh records are retained as source records. Only 497 belong to the 0–6 or 6–12-month newborn bands (344 + 153); 303 belong to bands beyond HerCare's intended first-year population. Any later HerCare-compatible experiment must define eligibility before evaluation rather than treating all 800 as an identical target population.

## Bangladesh data integrity findings

Checks use the downloaded dictionary and explicitly recognised English/Bangla response codes. They do not establish clinical validity of the questionnaire wording.

| Integrity check | PHQ-9 | Source EPDS |
| --- | ---: | ---: |
| Item sums disagree with stored total | 88 | 8 |
| Stored severity category disagrees with dictionary-defined total bands | 40 | 16 |
| Rows passing both checks | 681 | 778 |
| Positive/negative labels among rows passing both checks | 407 / 274 at score ≥10 | 346 / 432 at source score ≥13 |

Counts overlap: do not add the two failure counts to determine rejected rows. The outcomes file keeps the provided total, reconstructed total and category consistency flag. The source-specific research label is **null on any failed check**, not silently corrected or made negative. Labels represent screening thresholds, not clinical diagnoses or later depression probability.

The dictionary gives PHQ-style frequency responses for EPDS items, unlike the validated instrument's question-specific options used in HerCare. Therefore even an EPDS row passing arithmetic checks is not established as a comparable clinical EPDS measurement. The whole source remains research-only, with `clinical_promotion_allowed=false`.

No full measurement duplicates were found after excluding `sr`. One selected predictor (`can_confide`) is blank in one record. Other selected fields have recognised codes. **`None` is a valid source category** for no education, no income or no pregnancy loss; default CSV NA parsing would incorrectly erase it. The extraction reads with `keep_default_na=False` and retains these meanings.

## Code and generated files

The added code is isolated under `hercare_ml`; no Flutter or backend code was changed for this request.

```text
hercare_ml/
  research/
    source_catalog.json          25 reviewed sources, candidate parameters/access
    aggregate_estimates.json     selected published statistics, NOT patient rows
  scripts/
    download_research_data.py     bounded, checksum-verified public downloads
    export_research_catalog.py   study-level source/feature provenance CSVs
  training/
    research_features.py         reviewed source-specific CSV adapters + CLI
    longitudinal_features.py     real consented participant/time feature builder
  tests/
    test_research_features.py
    test_longitudinal_features.py
  data/raw/                      ignored original source files + provenance
  data/processed/                ignored extracted research tables/audits
```

Actual extracted outputs:

- [Bangladesh features](C:/Users/WSPL/Downloads/HerCare/hercare_ml/data/processed/bangladesh_v3_20261008/features.csv), [outcomes/flags](C:/Users/WSPL/Downloads/HerCare/hercare_ml/data/processed/bangladesh_v3_20261008/outcomes.csv), [audit](C:/Users/WSPL/Downloads/HerCare/hercare_ml/data/processed/bangladesh_v3_20261008/audit.json).
- [PERI_DEP features](C:/Users/WSPL/Downloads/HerCare/hercare_ml/data/processed/peri_dep_20261008/features.csv), [outcomes](C:/Users/WSPL/Downloads/HerCare/hercare_ml/data/processed/peri_dep_20261008/outcomes.csv), [audit](C:/Users/WSPL/Downloads/HerCare/hercare_ml/data/processed/peri_dep_20261008/audit.json).
- [Study-source evidence](C:/Users/WSPL/Downloads/HerCare/hercare_ml/data/processed/research_evidence_20261008/study_sources.csv) and [candidate-feature provenance](C:/Users/WSPL/Downloads/HerCare/hercare_ml/data/processed/research_evidence_20261008/candidate_feature_evidence.csv). **These are not clinical training observations.**

Run from `C:\Users\WSPL\Downloads\HerCare\hercare_ml`; choose an unused output directory each time:

```powershell
.venv\Scripts\python -m scripts.download_research_data
.venv\Scripts\python -m scripts.export_research_catalog --output-dir data\processed\evidence_new
.venv\Scripts\python -m training.research_features --source bangladesh_ppd_v3 --input data\raw\bangladesh_ppd_v3\PPD_dataset_v3.csv --output-dir data\processed\bangladesh_new
.venv\Scripts\python -m training.research_features --source peri_dep --input data\raw\peri_dep_dataset.csv --output-dir data\processed\peri_new
.venv\Scripts\python -m pytest -q -p no:cacheprovider
```

The downloader currently reports a failure for the PeerJ supplement if its public link again returns HTML. Successful verified files are preserved; no bogus XLSX is stored. Manually obtaining/uploading the actual supplement will allow inspection and a reviewed adapter. No schema or model has been fabricated for the missing workbook.

## More training rows from real observations

`training.longitudinal_features` generates one row per consented participant/prediction index, using **actual earlier data**, rather than fabricating extra mothers or recovery results. More windows increase the number of observations, not independent people.

For completed local days in 1-, 7-, 14- and 30-day windows it calculates:

- Means and field-specific observed-day coverage for mood, energy, sleep quality, social support, actual recorded sleep minutes/awakenings, aggregate device usage and therapy interaction minutes.
- Standard deviation and ordinary-least-squares slopes for multi-day windows. Slopes use elapsed calendar days, so irregular check-ins do not masquerade as consecutive days. A one-day window has no useless SD/slope columns.
- Negative/analyzed notification ratios using sums from matched observations, not averages of daily percentages. A zero denominator produces null.
- Latest prior EPDS/PHQ-9 totals, instrument version and age of each score.

The mathematical definitions are `mean = sum(x)/n`, `coverage = observed_days/window_days`, and `slope = sum((t-mean(t))*(x-mean(x)))/sum((t-mean(t))^2)`. Notification ratios use `sum(negative_count)/sum(analyzed_count)`. These describe observed records; their predictive value must be learned and evaluated, not assumed from a formula.

Future outcomes are separate: the actual assessment nearest day 14 within a ±3-day research window, its timestamp/version, and absolute change from a compatible earlier assessment. The window is a configurable research design, not a clinical guideline. Missing outcomes stay null; version-mismatched scores are not subtracted. No percentage improvement is labelled as validated recovery and no causal treatment benefit is inferred.

The input is a **de-identified, independently consented research export**, not direct access to production health records. Contract:

```text
schema_version: 1
data_kind: "real_consented_observations"
participants[]: participant_id (pseudonym), research_consent (boolean), timezone (IANA)
indexes[]: participant_id, index_at (timestamp with offset)
daily_observations[]: participant_id, date (local YYYY-MM-DD), available_at,
  optional mood_rating/energy_level/sleep_quality/social_support (1–5),
  sleep_minutes, sleep_awakenings, therapy_minutes,
  usage_permission, screen_minutes/social_minutes/late_night_minutes,
  notification_permission, notification_analyzed_count/notification_negative_count
assessments[]: participant_id, instrument (epds/phq9), version,
  performed_at, available_at, score (completed integer total)
```

Timestamps must include timezones. `available_at` is when a record/revision became usable, not merely its backdated self-report date. Late-entered history and later screening scores cannot enter earlier predictions. Duplicate participant/day revisions or duplicate assessment/index timestamps fail closed for upstream resolution. Export builders must produce actual daily sleep/activity aggregates and genuine permission states; the extractor does not fetch the database or infer missing telemetry.

Usage and notification permissions are independent. No permission means unavailable measurements, not a healthy zero. Private identity/content keys are rejected, no raw journal/chat/audio/notification content is exported, and only allow-listed numeric measurements enter features. Declared synthetic exports are rejected. Dataset creators must still attest source authenticity and research authorisation; a JSON field cannot prove that an observation is real.

```powershell
.venv\Scripts\python -m training.longitudinal_features --input data\raw\consented_hercare_export.json --output-dir data\processed\hercare_followup_new
```

**No actual prospective HerCare export was available or generated in this task.** This code was exercised with explicitly test-only fixtures, not represented as newly collected clinical data. There is no newly trained recovery model or new validated accuracy figure.

## Before using these tables in model training

1. Pick one target, population and horizon. Source-specific current-screening outcomes do not become day-14 recovery targets. Do not combine depression and psychosis endpoints.
2. Select predictors explicitly from each audit's `predictor_columns`/`selected_features`; never train on the outcomes table, identifiers, hashes, group keys or future timestamps.
3. Split participants before fitting transformations or balancing. Keep all HerCare windows from one mother in one group. For public data without verified IDs, feature-pattern grouping is a conservative proxy, not proof of subject independence. Keep sources separate for compatible external evaluation.
4. Fit numeric imputation, categorical encoding/scaling, missingness flags and feature selection on training folds only. Do not fill absent outcome labels. Extraction intentionally preserves predictor nulls; the existing curated training recipe already demonstrates training-only imputation.
5. Calculate class weights within each training fold. Do not copy/SMOTE/resample before splitting, balance validation/test data or claim generated rows are independent participants. More copied records do not fix lack of information.
6. Evaluate AUROC, PR-AUC, sensitivity/specificity, calibration/Brier score and interval estimates, including subgroup/site/temporal evaluation. An improvement in this experiment does not establish real deployment effectiveness.
7. Review inconsistent labels and nonstandard EPDS wording with the dataset creators/a qualified instrument reviewer before any clinical use. Do not auto-promote these research tables or estimates into the live model.

Published coefficients support hypothesis selection only. For example, the [Cureus study](https://doi.org/10.7759/cureus.86156) reports adjusted associations for a **combined PPD/psychosis case-control outcome**. Its odds ratios are not HerCare model weights. The estimate file preserves this definition, confidence intervals and source location. It does not reconstruct a joint distribution, regression intercept or individuals.

## Verification

- Both source-specific extraction commands completed on the real local files and produced separate predictor/outcome/audit outputs.
- The evidence exporter completed for 25 reviewed references.
- All **58 Python tests passed**, including existing runtime/community/change/training tests and new extraction tests for source coding, leakage, inconsistent labels, privacy, permissions, calendar windows, missing follow-up, duplicate/schema rejection and non-overwriting exports.
- Compilation of all four added Python modules completed.
- The live `.joblib` and metadata remain unchanged. No app, API server or mobile build was launched.

The spreadsheet skill guided preservation of original source data, code definitions, missing-versus-zero distinctions and independent checks. No source workbook was edited or claimed to be inspected when its download failed.
