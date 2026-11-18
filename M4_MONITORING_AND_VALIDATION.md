# M4 monitoring and 14-day forecast evaluation

## What the app reports

Risk Insights calculates a daily, rolling 7-day, rolling 14-day, and rolling 30-day overall report from the mother's saved records. Each report shows observed concern points, data coverage, the direction of comparable screenings, changes in supporting signals, and a suggested next step. The report uses the Karachi reporting date. The daily view compares today's entries with the preceding seven days. The other views compare with the immediately preceding window of equal length. The latest usable screenings and their dates are shown in every view because EPDS and PHQ-9 are periodic.

The composite is a versioned monitoring rule. Its weights are engineering choices for this release. The clinical instruments retain their existing scoring and their own follow-up pathways. The separate research outcome is the future EPDS score or later screening positivity. EPDS is intended for screening and follow-up assessment. [COPE EPDS screening guide](https://www.cope.org.au/health-professionals/screening-and-assessment-tools/using-the-epds-as-a-screening-tool)

| Input | Maximum points | Calculation and interpretation |
| --- | ---: | --- |
| Completed EPDS | 35 | 65% of the group measures latest total divided by 30. The remaining 35% measures a rise divided by 6 and capped at 1. Two successive rises across three screens add at most one effective rise point. |
| Completed PHQ-9 | 10 | Same calculation with a maximum total of 27 and its own cadence and screening result. |
| Mood and energy | 13 | Mood receives 9.1 points and energy 3.9. For each 1–5 rating, combine 65% of current low rating with 35% of the decline from the prior period. |
| Recorded sleep | 15 | Duration 4.5, quality 4.5, awakenings and awake minutes 3, bedtime and wake-time variability 3. Duration, interruptions, and quality combine level and deterioration. Timing is a comparison against the mother's own recent schedule using circular clock distance. A saved diary quality takes priority over the mood form's quality for the same day. A phone suggestion enters only through a saved sleep record. |
| Weekly finances, household relationships, and physical recovery | 15 | Five points each. The four-question check-in records the mother's experience over the past seven days. Use 85% of current severity and 15% of worsening, on a 0–3 scale. Recent explicit affordability and mother-in-law responses can fill missing finances and relationship items. |
| Perceived help and support gap | 5 | Daily social support receives 2.5 points. The weekly question about unmet help receives 2.5. |
| Private language signals | 5 | With opt-in, saved typed and imported journals, confirmed voice transcripts, and the mother's Hum-Raaz messages supply narrow first-person distress indicators. A day counts once across sources. Repeated cues can contribute after at least two observed days. One flagged day supplies no distress points. |
| Phone aggregates | 2 | One point for changes in screen time, social app minutes, late-night minutes, and app switching. One point for changes in negative, distress, and abuse notification ratios, using analyzed message count as the denominator. Total notifications are an audit/counting field. Permission and observations on earlier dates determine eligibility. Today's partial phone snapshot is excluded. Phone patterns alone cannot trigger a clinical or early-screening warning. |

The questionnaire offers four optional choices from no difficulty through severe difficulty, with a separate skip value. A mother can update today's answers without creating an extra record. Reports use the most recent submission in each seven-day block. Example topics include changed ability to afford essentials, tension with a partner or mother-in-law, help with care and household tasks, and recovery making daily care difficult.

Age, postpartum months at onboarding, education, household type, income band, supporter identity, delivery method, previous deliveries, living children, recorded complications, and baby sex are preserved as available background fields in the mother-owned API and represented as candidate inputs in the synthetic experiment. Current hardship, relationship strain, available help and recovery get the numeric weight in the live formula. Fixed traits, birth history and identity alone get zero points. Earlier clients serialized skipped parity and complications as zero and false. M4 marks those ambiguous historical values unknown. Names, city, search queries, language settings, and interface clicks have no monitoring weight. Instrument language and version are used to determine comparability. The research participation setting controls separate authorized research flows.

## Formula and report labels

For each eligible measurement calculate a concern value from 0 to 1. The report totals the measurement's concern multiplied by its assigned maximum points. Coverage is the sum of the available measurement weights and their available fractions. A missing comparison loses its trend fraction, and a missing input loses its contribution. The score always uses the fixed 100-point scale. A report with 24 observed points and 60% coverage has 40 unobserved potential points. Comparing raw totals across materially different coverage can be misleading.

The live implementation uses the following transformations. Let `C` be the current observed mean, `P` its prior-period mean and `clip(x)` limit a value to 0–1. When `P` is unavailable, the comparison term contributes no points and its coverage is absent.

| Measurement | Concern before weighting |
| --- | --- |
| Mood, energy, support rating, or sleep quality | `0.65 × (5 − C)/4 + 0.35 × clip((P − C)/2)` |
| Sleep duration | `0.60 × clip((420 − C)/240) + 0.40 × clip((P − C)/120)`, in minutes |
| Awakenings | `0.60 × clip(C/6) + 0.40 × clip((C − P)/3)` |
| Time awake in bed | `0.60 × clip(C/180) + 0.40 × clip((C − P)/60)`, in minutes |
| Bedtime or wake-time variability | `clip((C − P)/120)`, using mean distance in minutes to the prior circular center |
| Each weekly questionnaire answer | `0.85 × C/3 + 0.15 × clip((C − P)/3)`. Affordability maps to 0 or 3 and the in-law response to 0, 1 or 2 as eligible level-only fallbacks. |
| Private distress cues | At least two distinct flagged days for points. Use `clip(flagged days / ceil(window days × 3/7))`, with a minimum seven-day window. |
| Phone usage change | `clip((C − P)/scale)`. Scales are 180 screen minutes, 120 social app minutes, 60 late-night minutes, and 60 switches. The four shares are equal. |
| Notification ratio change | `clip((C − P)/0.40)` for each of the three ratios. Use at least five analyzed messages in each comparable window. The three shares are equal. |

For an illustrative daily calculation, EPDS rising from 6 to 9 contributes 35 × (0.65 × 9/30 + 0.35 × 3/6) = 12.95 points before rounding. Mood falling from a prior average of 4 to today's 2 adds 9.1 × (0.65 × 3/4 + 0.35 × 1) = 7.62. The same formula adds the other eligible contributions. Weekly and fortnightly results are recalculated from their date windows. Each periodic screening contributes once per report.

Daily measurements generally require at least 40% of the days in the relevant window, rounded up. Screening comparisons need the same instrument version and language and distinct dates near the app's 7-day EPDS or 14-day PHQ-9 cadence, allowing three days either side. A new or stale EPDS history can display records and findings. The composite is available once a fresh comparable EPDS pair exists.

- Screening direction uses actual comparable totals. The report can say screening scores fell and highlight deteriorating sleep and mood at the same time.
- A rise of four EPDS points, consecutive EPDS rises, or a smaller EPDS rise corroborated by worsening daily signals can prompt a screening follow-up below the configured elevated-screen cutoff. A PHQ-9 rise with multiple worsening daily domains can also prompt follow-up when an EPDS pair exists.
- An elevated screen can direct the mother to professional support. Active safety concerns take priority over report scores and content. A low score or better daily signals cannot cancel an active concern.
- Recommendations route to existing HerCare resources for the identified need. These include the screening schedule, Digital Wellbeing, the curated content feed filtered to practical education or soothing content, the care directory, and the existing crisis flow. Catalog cards appear after editorial review and publication. No external viewing history is needed.

## Synthetic training and evaluation

The seeded experiment generates synthetic, dated baseline and outcome records for 600 simulated mothers, split into 360 for fitting, 120 for calibration, and 120 for test. Each mother has three index windows. It evaluates a further 200 simulated mothers under changed generator assumptions. The model uses up to 50 candidate features to predict EPDS at a later observed date within 14 ± 3 days. The prediction yields four severity bands, new screening positivity for those below the research cutoff, and improvement/stability/worsening using a four-point margin. A future EPDS is never a predictor for its own outcome.

The comparison includes carrying forward the latest EPDS, EPDS-only ridge regression, and all-input ridge and gradient boosting. On the reference holdout the all-input ridge warning detected 76.2% of new positive screens, with a 19.4% false-alarm rate and 38.6% precision. EPDS-only ridge detected 59.5% with 21.3% false alarms. Under changed generator assumptions the all-input warning detected 55.9% with 24.1% false alarms. The all-input ridge's reference score error averaged 2.74 EPDS points. Three-way direction accuracy was 62.5%, and worsening recall was 26.7%.

The ridge models use regularization alpha 10. Histogram boosting uses 100 iterations, up to 8 leaves, a 20-row minimum leaf and L2 regularization 2. The seed is 42. Synthetic severity bands are 0–8, 9–12, 13–18, and 19–30. The incident warning uses a threshold set on calibration participants below EPDS 13 at baseline.

These figures describe simulated outcomes. The live API reports no future probability. To measure real-world performance, collect actual dated follow-up assessments under the applicable study process, compare with the existing screening-only baseline, and evaluate sensitivity, false alarms, calibration and subgroup performance on held-out participants before enabling a forecast. The app does not send private texts, recordings, or chats to this training pipeline.

See [the generated synthetic evaluation](hercare_ml/artifacts/experiments/m4_synthetic_verified/synthetic_report.json) and [the reproduction instructions](hercare_ml/README.md#m4-synthetic-forecast-experiment).

## Deployment and FYP demonstration

1. Run the backend's existing migration command `npm run migrate` against the target HerCare database before deploying the new backend. Migration `022_m4_monitoring.sql` adds the questionnaire and prospective private text-signal storage.
2. Use a mother account with basic monitoring consent and open **Risk Insights**. Complete two compatible scheduled EPDS screenings or use a prepared demonstration account with dated sample assessments. Use separate demonstration data for a below-cutoff rise, falling EPDS with worse sleep/mood, elevated screening, and insufficient data.
3. Record mood and sleep, answer the optional questionnaire, and check each report tab. Enable private text signals if demonstrating journaling or Hum-Raaz. New eligible entries contribute from that point forward. Withdrawing consent clears the derived M4 text signals. The source module's ordinary history and safety handling follow their own controls.
4. Present the synthetic report separately from the in-app monitoring example. The live monitoring path requires Flutter, Node and PostgreSQL. Its score does not depend on a Python forecast artifact.

The migration and authenticated API were exercised against temporary PostgreSQL with fabricated accounts. The test covers all four periods, dated questionnaire updates, authorization, source deletion, confirmed voice, and prospective text consent and withdrawal. Python tests exercised synthetic data generation, participant partitioning, and rejection of the experimental artifact by the clinical-data and runtime loaders. A device build and target database deployment are separate release steps.
