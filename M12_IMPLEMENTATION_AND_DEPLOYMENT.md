# M12 peer community: completion and deployment

Updated 2026-10-15. This supersedes the old statement that the AI adapter exists but no weights are provisioned. Implemented/tested software is not a claim of completed public deployment or independently validated moderation.

## What is implemented

- Community-only pseudonyms; coping, recovery, family, bonding and medication-experience topics; English/Urdu posts and replies; supportive reactions and solidarity counts.
- Versioned guidelines, encrypted post bodies, bounded cursor pages, reports, bilateral blocks, deletion and personal post/reply history. No journals, chat transcripts, recordings or clinical scores are imported into peer posts.
- **Actual self-hosted AI triage**, not a placeholder: five topic scores for self-harm, harassment, spam, medication/treatment instructions and supportive experiences. Rules remain an independent safety/privacy fallback. AI scores are hints for a human moderator, not clinical probabilities.
- All posts/replies remain pending until human review. Production also requires successful AI triage before publication by default. AI outage, saturation, missing token/model, bad scores, incomplete-text responses or timeout never bypass review. Removal and private submission remain available during an outage.
- Protected moderator status, oldest-first queue, documented review decisions, alias-only member suspend/restore controls, and rechecks of current author/moderator/parent eligibility after inference and before publication. AI inference does not hold a database transaction open.
- Scheduled professional text Q&A, host answers, date/time pickers, cancellation and closed-session read-only behavior. Scheduling retries use a stable request ID. The operator must verify the named professional; software does not manufacture credentials.
- Account-bound Flutter routes/dialogs and HTTP requests prevent stale replies/drafts/moderator lists from moving between accounts. Private drafts stay in memory, never a shared disk cache. Permission loss clears retained content; unavailable/deleted discussion data is discarded.
- Existing theme and Urdu language controls retained; layouts exercised at compact widths, keyboard insets and increased text sizes. Community request bodies and exception text are excluded from error logs. The account-binding header is allowed by web CORS.

No new migration or mobile dependency is required. Do not edit applied migrations 001–020. Existing migration `010_peer_community.sql` must already be applied on the target database.

## Model and honest evaluation

The public [model author's multilingual MiniLMv2-L6 MNLI/XNLI model](https://huggingface.co/MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli) is MIT-licensed and distilled for smaller/faster inference. The trade-off is weaker performance than the author's larger mDeBERTa alternative. Its published NLI results are not community moderation accuracy.

- Revision: `0a71e92a985b6e1ad1828cf67ce9c459639c1dca`.
- Runtime: existing CPU ONNX Runtime and Rust tokenizer, two CPU threads by default, one inference slot per worker; no Torch/Transformers, remote Python, pickle weights or request-time downloads.
- Provisioned local files: 445,217,532 bytes including tokenizer/config/model card. **Server only**, ignored by Git/Docker context; nothing is added to the phone package.
- Pinned code-level SHA-256 values plus a provenance manifest are checked on cold loading. Mount weights read-only. Changed model files require a deliberate reviewed source/code revision, not a silent replacement.
- Token overflow windows preserve the whole bounded post, including its end. A token-work limit rejects excessive work rather than silently truncating it. Scores use maximum entailment-vs-contradiction across windows, not a validated clinical formula.
- `research/community_challenge.json` contains 42 explicitly authored engineering examples: 14 each in English, Urdu and Roman Urdu, including negation, quoted bullying, medication experiences and privacy reminders. These are **not patient data, independently labelled evaluation data or training data**.
- Fixed 0.5 expected-topic hints fired on 6/10 English, 10/10 Urdu and 6/10 Roman Urdu straightforward authored topic cases. Expected topic was among the top three on 10/10, 9/10 and 8/10 respectively. These small, same-author checks are not accuracy estimates and were not used to tune a threshold.
- On this machine, the smoke run measured 1.8995-second cold readiness, 0.0379-second warm median and 0.121-second warm 95th percentile over those short examples. A 2,129-character Urdu overflow example took 1.8461 seconds. This is **not a production latency guarantee**. The long example's self-harm score was below 0.5 despite a danger phrase: the separate rules and human review must not be removed.

The model was pretrained/fine-tuned by its author for NLI; it was **not fine-tuned on HerCare posts**. Representative independently reviewed moderation examples, language-specific evaluation and operator policy review are required before public use. No 90%/perfect/clinical validation claim is made.

## Deployment

Use Node 22+ (verification also uses the bundled Node 24 runtime), PostgreSQL, HTTPS mobile API, stable encryption keys and real moderator accounts provisioned by an authorised operator. Public registration cannot grant admin access.

From `hercare_ml`, provision server artifacts and dependencies:

```text
python -m pip install -r requirements-community.txt
python scripts/community_download.py
python scripts/community_smoke.py
```

The script downloads only pinned public artifacts, checks existing outputs rather than silently overwriting different files, and starts no service. The existing ML Dockerfile installs the CPU runtime, but weights are deliberately excluded from its context. Mount the provisioned directory at `/app/artifacts/community/minilm_v1:ro` in deployment; provision it before accepting review traffic.

Python configuration (`community.env.example`):

```text
COMMUNITY_MODEL_PATH=/app/artifacts/community/minilm_v1
COMMUNITY_CPU_THREADS=2
ML_SERVICE_TOKEN=<strong internal shared secret injected by deployment>
```

Node configuration (`hercare_backend/.env.example`):

```text
COMMUNITY_MODERATION_URL=https://YOUR-PRIVATE-ML-HOST/v1/community/moderate
COMMUNITY_AI_REQUIRED=true
ML_SERVICE_TOKEN=<same internal shared secret>
```

An explicitly configured `ML_SERVICE_URL` is also supported as the base when `COMMUNITY_MODERATION_URL` is absent. Production moderation connections require HTTPS. Keep the Python service private with network controls; community endpoints require the token even in development. This is an internal service credential, **not a paid AI-provider API key**. Never put it in Flutter.

Probe private `GET /v1/community/ready` before sending review traffic to warm/check the model. `GET /api/v1/community/moderation/status` gives administrators readiness without exposing paths, hosts or tokens. `COMMUNITY_AI_REQUIRED=false` is an explicit **human-only degraded mode**, not completion of the AI scope. Mandatory human publication approval is never disabled.

Start/deploy services only when the operator requests it. This task does not launch the app, install/build an APK, start a persistent server, send a real notification, create public posts, change real roles or apply migrations.

## Verification and release gates

Verification on the final implementation:

- Full Python: **177 passed**, including strict private-token, file-integrity, nonfinite/bad-output, semaphore, token-overflow/tail and work-limit checks. Existing Starlette/AnyIO and SciPy solver-option warnings remain non-failing.
- Full Flutter: **341 passed**; full analysis reports no issues. M12 has **36 focused tests** (12 existing + 24 reliability checks), including account changes/logout/guardian exclusion, late responses, open-dialog disposal, 403 purging, inaccessible threads, exact post/Q&A retries, member restoration, cancellation/read-only sessions, language changes and 320×480 English/Urdu 200%-text/keyboard dialogs. Two actual dialog overflow findings were corrected by scrolling title, fields and actions together.
- Backend Node 24: full automated test files pass; **160 passed, 18 optional checks skipped**. Full backend ESLint passes. The unrelated manual `test-chat.js` is deliberately excluded: it is not a safe automated unit test.
- Separately enabled **actual model/FastAPI–Node contract: 1 passed**, covering authenticated readiness and all three languages without an HTTP listener. **PostgreSQL M12 rollback integration: 1 passed**, with many assertions covering encryption, publication privacy, blocking, pagination, quotas, exact/changed/deleted retries, FIFO queue, Q&A, AI outage/recovery and author/admin/parent eligibility changes during inference. All synthetic account/content mutations are rolled back.
- The installed app CORS middleware is tested directly for permitted/denied origins and the account-bound header without a listener/database request. Model reprovisioning verified existing pinned files without overwriting; dependency and diff checks pass.

Automated suites may use short-lived test listeners with synthetic/stub inputs; they close afterwards. They are not a mobile app launch, persistent backend/model deployment, physical-device acceptance or load/security/clinical validation.

Before public launch, supply staffed moderation with response targets, verified Q&A professionals, policies/retention/support contacts, production secrets/weights, staging device/web/network testing, load/security review and independently reviewed representative moderation evaluation. AI-only emergency monitoring is not offered; community posts never automatically contact a guardian. Community refresh remains explicit/on-entry/pull-to-refresh/action-driven; live reply push/WebSocket updates are optional extensions, not implemented scope requirements. Hosting/storage/moderator work can cost money even though the AI model has no paid inference API.
