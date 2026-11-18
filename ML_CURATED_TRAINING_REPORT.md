# HerCare curated data extraction and training results

Completed 8 October 2026. The available original PERI_DEP CSV was audited, necessary predictors were extracted with their actual meanings, and two isolated current-screening research candidates were trained. The daily percentage-improvement prototype has not acquired a learned clinical target: this CSV has no dated previous/current wellbeing history or independent later recovery outcome. Missing future outcomes were not fabricated or imputed.

## Selected parameters

| Research parameter | Exact PERI_DEP source | Selection and app compatibility |
| --- | --- | --- |
| `age` | Age | Relevant baseline context. Matches the app age question. |
| `number_of_children` | Total Number of Children | Relevant maternal/family context. Kept under its exact meaning; app asks previous deliveries, which is not equivalent. |
| `education_level` | Female Education | Relevant background/context. Whitespace/case normalised into stable education codes matching the app categories. |
| `household_type` | Family System | Joint/nuclear context. Matches the app household question. |
| `basic_needs_financial_strain` | Sufficient Money for Basic Needs | Yes=0, no=1. Actual affordability measure; income bracket was not substituted. |
| `mother_in_law_relationship_quality` | Relationship with Mother in-law | Poor=0, moderate=0.5, good=1. Actual relationship rating; supporter identity was not substituted. |

The six-field research profile uses all six exact source parameters. The app-matched profile uses only age, education and household type. Both predict the source's current `Labelling` field (`depressed=1`, `not=0`). Neither predicts improvement, clinical diagnosis or a future 14-day outcome.

PHQ-9 item responses, the `Scalling` total and `Labelling` were excluded from predictors to avoid predicting a screening label from its own components. Other source columns were excluded because they are not part of the chosen feature contract or lack an equivalent app measurement. Dataset identifiers/hashes and partition metadata are not model inputs.

Adding the source PHQ-9 answers could make this contemporaneous classifier appear more accurate while merely reconstructing the screening calculation. It would not solve recovery forecasting.

## Data audit and cleaning

- Original file: 14,008 rows; SHA-256 `3d2efa3aaea9e4ba3a404c6dbbd4a82a4c832c7cd578de10ff2ae28967062c42`.
- Whitespace/case normalised and explicit blank/null tokens recognised; duplicate column names fail validation.
- 7,000 repeated full source rows removed, leaving **7,008 retained source records**. These are unique normalised rows, not a verified count of unique mothers.
- Known classes after cleaning: 2,467 negative and 4,541 positive. No invalid/missing target codes were encountered. Future unknown/missing labels are excluded and reported, never filled as negative.
- Missing selected predictors after cleaning: age=2; affordability=2; other selected predictors=0. One non-missing age outside the app's permitted 15-55/integer range was marked missing and reported rather than accepted as a valid value.
- Retained records form 3,455 six-feature patterns; 962 patterns have both target labels. These conflicting demographic patterns remain in the data; labels were not forced to agree.

Full-record deduplication uses all normalised source columns internally. It does not discard different participants simply because their selected demographic features match. To reduce exposure to repeating selected patterns during evaluation, identical six-feature patterns are grouped into one partition. Without participant IDs this is a conservative proxy test, not proof of participant independence or an external validation cohort.

## Missing values and class balancing

Feature imputation is fitted inside each training fold and finally on the training partition alone. Test/calibration values never determine medians, category encoding or scaling. Numeric medians in the final six-field candidate are age=28, children=2, affordability strain=1 and relationship quality=0. Categorical blanks use an explicit `__missing__` category; all predictors also have missingness indicators. Unknown categories are safely encoded. All exported processed matrices were verified to contain no missing or non-finite values.

Missingness handling and class imbalance are different tasks. Class balancing uses `weight_class = N_training / (2 * count_class)` passed to each estimator. For the final 4,110-row training partition, both classes have effective total weight **2,055**. Class weights are recomputed separately inside every training fold. No SMOTE, synthetic patient generation, or global pre-split oversampling was used. Calibration/test retain their observed class proportions.

## Split and training workflow

| Partition | Rows | Negative | Positive | Six-feature groups |
| --- | ---: | ---: | ---: | ---: |
| Training | 4,110 | 1,454 | 2,656 | 2,061 |
| Calibration | 1,350 | 483 | 867 | 686 |
| Untouched test | 1,548 | 530 | 1,018 | 708 |

The group-aware split uses fixed seeds. Because groups differ in size, these counts are approximate proportions rather than exact 60/20/20 percentages. Six-feature group identities do not cross partitions. The three-field profile may still repeat a coarser three-field pattern across partitions; it uses the same six-field grouping and test cohort so the two experiments can be compared fairly. No clinical participant identity was available.

For each profile, regularised logistic regression, a 200-tree random forest and 150-stage gradient boosting were compared using three group-aware folds inside the training partition. All three receive training-only balanced sample weights. Gradient boosting had the highest mean training-fold ROC-AUC for each profile and was selected before viewing the test scores.

The selected model was refitted on training data, then its probabilities were sigmoid-calibrated on the separate calibration partition. An exploratory threshold maximising calibration balanced accuracy was also calculated. Calibration/threshold selection share that development partition; their apparent performance is not reported as independent validation. The final test partition was used to report both the default 0.5 threshold and the research threshold. The latter is not a selected clinical operating policy.

## Honest held-out results

| Profile | Test ROC-AUC | Accuracy at research threshold | Balanced accuracy | Sensitivity | Specificity |
| --- | ---: | ---: | ---: | ---: | ---: |
| Six exact source features | 0.5188 | 50.58% | 50.71% | 50.29% | 51.13% |
| Three exact app-matched features | 0.4876 | 37.53% | 49.16% | 12.28% | 86.04% |

Research thresholds were approximately 0.6457 and 0.6425 respectively. These results are near chance in discrimination. At the default 0.5 threshold, both calibrated models predicted every test record as positive: accuracy=65.76%, balanced accuracy=50%, specificity=0%. An always-positive classifier also scores 65.76% accuracy on this test set. Ordinary accuracy therefore supplies no evidence of useful prediction.

The earlier live baseline's AUC=0.6231 was obtained using a different row-split protocol with the original duplicated file. It cannot be compared as if it used this same test cohort. The stricter experiment does not establish that source rows are fabricated, but it exposes how weak these selected static features are for the held-out patterns.

Neither new candidate is suitable for promotion as a reliable health predictor. Data cleaning and class balancing improve the validity of the experiment; they do not create missing predictive signal. We did not tune against the test results to improve their headline metrics.

## Generated files and implementation

All selected observations, processed matrices and fitted candidates are in the ignored research directory:

- [Selected source-matched observations](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/peri_dep_curated_20261008/selected_features.csv). Predictor blanks are preserved here so missingness remains auditable; training code fills them after the split.
- [Six-feature processed training matrix](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/peri_dep_curated_20261008/source_matched_six_train_processed.csv), with encoded/scaled features, label and sample weight.
- [Full data audit](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/peri_dep_curated_20261008/data_audit.json).
- [Six-feature candidate metadata](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/peri_dep_curated_20261008/source_matched_six.json) and [three-feature candidate metadata](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/peri_dep_curated_20261008/app_matched_three.json).
- [Complete experiment summary](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/peri_dep_curated_20261008/experiment_summary.json).
- [Extraction contract](C:/Users/WSPL/Downloads/HerCare/hercare_ml/training/curated_data.py) and [training recipe](C:/Users/WSPL/Downloads/HerCare/hercare_ml/training/curated_train.py).

Each profile also has a `.joblib` research artifact and separate calibration/test matrices. Artifacts use a `research_pipeline` key, so the existing live `ModelRuntime`, which expects `pipeline`, cannot silently load them as production models. The original raw data, existing live artifact, API configuration and Flutter screens were preserved.

Verification included extraction/label/duplicate/split/imputation tests, actual candidate training, reloading both saved candidates and reproducing the test AUC, and checking all processed partitions for missing values. These checks validate the software and numerical reproducibility, not clinical performance.

## What is still needed for the personal improvement model

The percentage-change formula can already calculate a descriptive comparison from actual app records. Training its weights or forecasting future change requires a separately authorised longitudinal dataset containing pseudonymous participant IDs, local observation dates, real daily mood/energy/sleep/support observations, dated screening totals and instrument versions, and later screening or clinician-defined outcomes. Optional sleep/device/activity features need timestamps and coverage flags.

There are no such follow-up rows in the available PERI_DEP file, and no other relevant training CSV was found locally. This turn did not export private app accounts, invent missing daily histories, fill entire unavailable fields with medians, or turn model predictions into recovery labels. Public cross-sectional records do not become recovery histories through imputation.

References for the mathematical/library behaviour used: [scikit-learn 1.6 imputation](https://scikit-learn.org/1.6/modules/generated/sklearn.impute.SimpleImputer.html), [stratified group splitting](https://scikit-learn.org/1.6/modules/generated/sklearn.model_selection.StratifiedGroupKFold.html), and [gradient-boosting sample weights](https://scikit-learn.org/1.6/modules/generated/sklearn.ensemble.GradientBoostingClassifier.html). Source dataset: [PERI_DEP](https://zenodo.org/records/11403247).
