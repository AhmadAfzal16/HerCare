# Hum-Raaz implementation and model card

Updated 9 October 2026. This reports implementation and engineering evaluation, not clinical validation or a completed efficacy study.

## Result and limits

Hum-Raaz now has a dedicated mother-facing interface and private server-side conversation history. It is separate from M7 guardian messaging. Replies support English, Urdu and Roman Urdu; the default follows the app language. Limited phone-side support works without a model download, server score access or notification delivery.

The server implements constrained retrieval/dialogue with an optional self-hosted open-weight language-model selector. The selector can return only a known evidence-card ID or abstain. The application displays original source-traceable response text, not arbitrary generated medical advice. This is **not an unrestricted generative therapist**, a foundation model created from scratch, or a clinically validated intervention.

The application-specific retrieval relevance model was actually trained. The pretrained Qwen model was downloaded and tested, **not fine-tuned**. Knowledge indexing, prompt customization, retrieval training and language-model fine-tuning are different operations; they must not be conflated in a paper.

## What was built

| Requirement | Implementation | Boundary |
| --- | --- | --- |
| Server-based bot | Private `/api/v1/chatbot` Node routes and `/v1/chatbot/reply` Python endpoint | No third-party AI provider or AI API key; internal authentication/encryption secrets are still required. |
| Phone offline support | Original fixed three-language coping/help cards, memory-only conversation | Clearly labelled limited offline support, not live AI. No score reads, offline push or automatic later upload. |
| Past/current conversations | Encrypted sessions/turns, pagination, deletion and account-isolated screen state | Full server archives are retained until deletion; inference uses bounded recent context, not every historic message verbatim. |
| Personalization | Separate versioned default-off consent; dated mood, screening, risk and journal-sentiment aggregates | No raw journal, audio or guardian-message access. Scores are kept in their original units. This is not research/training consent. |
| Withdrawal | Consent revision checks before/after inference; old personalized assistant turns/state excluded from new inference | Already displayed/archived replies can contain earlier scores until the session is deleted. A running local request cannot be “unsent.” |
| Multi-turn support | Bounded prior user-message recall, topic continuation and structured optional thought reflection | Small curated topic set, not free-form psychotherapy. |
| Safety | Independent multilingual cues, recent screening safety override, private crisis guidance and state continuity | Heuristic rules, not a validated suicide/psychosis/infant-risk classifier. No invented emergency numbers. |
| Guardian privacy | No raw bot conversations in guardian reports; M10 urgent sharing defaults off per mother/current link | Since 2026-10-11, eligible explicit personal self-harm rules use M10's separate safe-recipient confirmation. General Tier2 or model flags alone cannot authorize disclosure; abuse/refusal/infant cues retain confidential help. See the M10 report for residual limits and review requirements. |

Conversation encryption uses AES-256-GCM with account/session/record-bound associated data. Cross-account ciphertext swapping fails authentication. Session ownership is checked server-side, stable request IDs prevent duplicate sends, and one in-flight reply per session protects turn order. Missing/busy inference produces an explicit unavailable or retrieval-fallback state, not a fabricated successful model reply.

Deleting a bot session removes its live conversation/request/context copies. Other care/crisis records and controlled backups have their own retention obligations. No private patient conversation, journal or hospital record was used as training data or added to research exports.

## How the chatbot works in simple words

1. The phone sends the mother's authenticated message and selected reply language to her own server.
2. The server checks ownership and safety, loads bounded private conversation context, and reads aggregate scores only if she separately consented.
3. The Python service finds relevant HerCare/support knowledge. It can use the local Qwen model to select a topic, but it cannot display invented model prose.
4. A response policy selects the three-language source card or a short reflection step. Insufficient evidence gives a clarification/abstention, not a diagnosis.
5. Personalization explains dated scores separately and can offer a smaller support step when recorded mood is low. A current screening safety positive bypasses ordinary coping; positive mood does not cancel safety.
6. The reply and state are encrypted in the mother's server history. Offline phone replies are explicitly limited and stay in temporary screen memory.

The selector receives a compact topic catalogue and bounded conversation text. Numeric aggregate explanations are produced deterministically outside the language model; they are not converted into a fused condition probability. A statement that the mother is safe is recorded as her report, not medical clearance. Starting a new conversation resets dialogue state but does not resolve clinical care records.

## Training and provenance

Knowledge: `hercare_ml/knowledge/chatbot/cards.json`, version `hum-raaz-kb-v1`, 12 topics, three response languages. Topics cover the assistant's role, privacy, test cadence, mood/journals, interpretation of research scores, practical support, bonding, thought reflection, grounding, sleep recording, cultural respect and app activities.

Content is original concise text with source links, not wholesale copies of manuals or patient conversations. Source-check status is recorded, but qualified clinical and bilingual review remains pending. Authoritative references include [NHS postnatal support](https://www.nhs.uk/mental-health/conditions/postnatal-depression/), [bonding information](https://www.nhs.uk/best-start-in-life/baby/baby-basics/bonding-with-your-baby/building-a-close-relationship-with-your-baby/) and [thought-reflection guidance](https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/self-help-cbt-techniques/reframing-unhelpful-thoughts/). Citing these sources does not imply NHS approval of HerCare.

Custom retrieval training uses word/bigram and character 3–5-gram TF-IDF, then a balanced logistic relevance ranker on word similarity, character similarity and their interaction. There are 72 original authored training queries and 864 query/card pairs (72 relevant pairs, 792 non-relevant). Another 36 queries tune the selection; a separate 36 report test routing. No missing “true answer” was invented from user records and no clinical patient class was oversampled.

The development-selected method was character retrieval, not the learned ranker. On the small same-author held-out query set it achieved **55.56% top-1 retrieval and 91.67% top-3 retrieval**. The hybrid and trained ranker achieved 58.33% top-1, but were not selected using the test results. These weak/limited scores are disclosed, not promoted as production or clinical accuracy. Out-of-domain boundaries and abstention checks are engineering safeguards; their thresholds and language coverage still need independent evaluation.

Experiment: [retrieval report](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/hum_raaz_retrieval_20261008/report.json). The runtime index is cached, hash-bound to the knowledge source and operator-provisioned. A clean checkout contains only its `.gitkeep`, not local experimental weights. The Dockerfile now includes knowledge and the provisioned retrieval directory; no Docker image build was performed here.

## Local language model and actual checks

Model: `Qwen/Qwen3-4B-Instruct-2507`, Apache-2.0 base model, community `unsloth` Q4_K_M GGUF quantization. Provisioned public revision `a06e946bb6b655725eafa393f4a9745d460374c9`; 2,497,281,120 bytes; SHA-256 `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597`. Runtime: checksum-verified CPU-only `llama.cpp b11510` for Windows x64.

The [author model card](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507) supports the model's general multilingual capabilities and licence. It does not establish postpartum Urdu/Roman Urdu clinical quality. The quantization provider and exact source/hash are recorded by `scripts/chatbot_download.py`; the 2.5 GB weights are ignored by Git and are not bundled into the phone.

Six known-example native CPU checks returned the expected structured card IDs in all three languages. These questions overlap the source examples: **6/6 is a runtime smoke check, not an independent benchmark or 100% chatbot accuracy**. An initial test harness suppressed output with a logging flag; its failed report is retained, not concealed.

The compact prompt reduced measured cold per-case latency from roughly 15–39 seconds to **11.56–15.80 seconds** on this Windows development computer with four CPU threads. Each case reloads the model. This is not production p95 latency, a throughput benchmark, or a guarantee for another server. The compact catalogue and strict JSON card-ID grammar reduce token work and prevent free-form prescriptions, fabricated scores, citations or phone numbers from being displayed.

Reports: [initial corrected smoke run](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/hum_raaz_local_smoke_20261009_v2/report.json), [compact smoke run](C:/Users/WSPL/Downloads/HerCare/hercare_ml/artifacts/experiments/hum_raaz_local_smoke_20261009_compact/report.json). No persistent model server, app launch or deployed network test occurred. Local HTTP model-server requests were contract/mocked-tested; actual native inference was tested through the command-line runtime.

## Existing ML model audit and corrections

The preserved live depression artifact is a soft-voting ensemble of logistic regression, random forest, gradient boosting and a small MLP. Its six trained inputs are age, number of children, education, household type, basic-needs affordability and mother-in-law relationship quality. **EPDS, PHQ-9, mood, sleep and telemetry do not become trained predictors merely because the API carries them.** Current contextual display and safety rules use those measurements separately.

Historic internal metrics are 66.42% accuracy and ROC-AUC 0.6231, with weak balanced accuracy/specificity and row-splitting limitations. The stricter curated PERI_DEP experiments were near chance. The separate Bangladesh first-year/full-source experiment achieved 78.31% accuracy and AUC 0.8345 on 83 test rows, but the four shared app-input models performed poorly. That model was not promoted or pooled indiscriminately into the deployed ensemble.

The review identified a bypass in the legacy `training.train --task trajectory` path. It is now disabled for CLI and direct calls, so a CSV with a conveniently named outcome cannot produce a purported live future artifact using row-random splits. Genuine follow-up research must use `training.forecast_train`, with provenance, day-14 ±3 dates, missing-target exclusion and participant-held-out partitions. No genuine two-week model has been trained.

Baseline weights/metadata are unchanged. Risk category thresholds remain engineering bands, not validated clinical action thresholds. No fabricated clinical confidence is exposed. Probability-based automatic escalation remains blocked without external validation/approval. Sentiment models estimate tone, not clinical distress; recorded “2% change” is an arithmetic index comparison, not proof of depression recovery or treatment efficacy.

## What can be claimed in a paper

A defensible description is **“HerCare: a privacy-controlled multilingual postpartum support system with constrained retrieval dialogue, consented score context, limited offline support and exploratory screening-risk estimation.”**

Separate the contributions and experiments: encrypted ownership/consent, retrieval relevance, local structured routing, language quality, safety/abstention, historical risk classification, descriptive change and eventual intervention outcomes. Do not describe this as a new clinically validated diagnosis/prevention formula, a therapist trained from scratch, a proven 14-day forecaster or a treatment that inherits the effects of Woebot/Wysa trials.

The [research and publication review](C:/Users/WSPL/Downloads/HerCare/CHATBOT_RESEARCH_AND_PUBLICATION_REVIEW.md) lists older trials, maternal chatbot evidence, dataset licences/access and scientific gaps. EmpatheticDialogues has noncommercial terms; ESConv is academic-research-only. CounselChat/MedDialog content rights need confirmation. MedQuAD offers licensed general medical Q&A subject to its exclusions, not postpartum counseling dialogue. Existing Urdu/Roman Urdu sentiment data do not train empathetic medical responses. No suitable clinician-reviewed three-language postpartum conversation corpus was verified.

Before clinical claims: obtain qualified bilingual content/safety review; create an independently authored held-out dialogue set; measure routing/abstention, prohibited-advice failures, source faithfulness and real load latency; externally validate risk calibration/discrimination with appropriate participant/site/temporal separation; obtain approved real follow-ups for forecasting; and use an appropriate study/control design for treatment or prevention efficacy. Published evidence informs the design but does not validate HerCare automatically.

For the prediction-model paper, use [TRIPOD+AI reporting guidance](https://www.bmj.com/content/385/bmj-2023-078378) and [PROBAST+AI quality/risk-of-bias assessment](https://www.bmj.com/content/388/bmj-2024-082505). These describe transparent reporting and appraisal, not automatic certification or proof of effectiveness. Prespecify outcomes/splits, report calibration and uncertainty, publish limitations and distinguish model development from independent validation.

Research collection/export remain disabled. User conversation storage is not authorization to train on it. Server deployment capacity, retention/backups, safe-recipient crisis policy and clinical governance remain operational responsibilities.

## Verification and deployment handoff

Migration `016_hum_raaz_chatbot.sql` was applied locally on 9 October 2026 using the existing checksum-aware runner. It creates the chatbot tables without pre-granting consent or changing existing care records. Do not edit that applied migration; future database changes need a new migration.

Final automated checks include **103 passing Python tests**, **92 passing Flutter tests**, and **60 passing default backend tests with 9 opt-in suites skipped**. A separate focused run passed **9 chatbot tests**, including actual PostgreSQL rollback fixtures and the real Python-to-Node three-language contract. Changed Flutter static analysis, backend lint, source compilation and patch-whitespace checks passed. Existing depression model artifact/metadata hashes remain unchanged. The final UI checks caught and fixed loss of the privacy/history panel's expansion state after opening a saved conversation; its deletion regression now passes. A test-only Windows temporary-directory permission problem was avoided with a fresh workspace-local pytest directory, not by modifying application behavior.

No real account was opted into personalization/research by this work, no private conversations were used for training/export, no real guardian push was sent, and no application/device/persistent service was launched. The local-model feature is provisioned and CLI-tested, but a real deployed HTTP model-service/device round-trip, production load test, Docker image build and clinical evaluation were not performed.

To enable constrained local-model selection later, start the separately provisioned CPU model process on the same host/network namespace, bind it to loopback and use alias `local`. Example from `hercare_ml` on this Windows development machine (not executed):

```powershell
artifacts\chatbot\runtime\b11510\llama-server.exe -m artifacts\chatbot\models\qwen3_4b_q4.gguf --alias local --host 127.0.0.1 --port 8081 -c 4096 -t 4 -ngl 0 --parallel 1 --jinja --reasoning off
```

Then configure the Python process with `CHATBOT_GENERATION_ENABLED=true` and `CHATBOT_LLM_URL=http://127.0.0.1:8081`, and matching strong `ML_SERVICE_TOKEN` in Node/Python. Keep the llama process private; do not expose it directly to the phone. The Node-to-Python connection requires HTTPS outside loopback. Linux deployment requires the matching trusted Linux runtime, not the Windows executable copied into a Python Linux container. For isolated containers, the local selector must share a network namespace or have a purpose-built equivalent private boundary; do not weaken its loopback restriction to call cloud providers.

If the model process is off, the bot transparently uses bounded retrieval support. If the private Python service is unavailable, the user gets an explicit failure/retry and can choose limited offline support. Since M10 on 2026-10-11, the former `CHATBOT_GUARDIAN_ALERTS_ENABLED` prototype gate is obsolete: eligible rule-based alerts require M10's separate, default-off, current-link safe-recipient confirmation, active sharing consent and event-bound policy. No patient permission is pre-granted; model flags alone do not authorize sharing. See `M10_CRISIS_IMPLEMENTATION_AND_DEPLOYMENT.md` for withdrawal, delivery and clinical-review limits. Hosting/RAM/CPU/storage still cost resources even though there is no hosted AI per-request API fee.
