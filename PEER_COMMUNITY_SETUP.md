# M12 — moderated peer community

## Implementation

The mother dashboard now opens **Peer community**. Mothers must finish onboarding and accept versioned community guidelines. Existing administrator accounts open the community interface from the role-aware home screen; the menu includes the moderation queue and scheduled expert Q&A. No account has been granted administrator privileges automatically.

The module uses the existing Flutter theme, authenticated Node API and PostgreSQL database. No Firebase database, subscription service, video SDK or additional mobile dependency is required. It includes:

- Random aliases and community-only member identifiers (not real user identifiers).
- Coping, recovery, family support, bonding and medication-experience topics.
- English/Urdu posts and replies in one community; supportive reactions and solidarity counts.
- Guideline acceptance, reporting, bilateral blocking/unblocking, personal post history and deletion.
- Mandatory review before publication, moderator decisions with reasons, optimistic version checks and audit records. Moderators can suspend/restore a member from their queue item; restoration of an account without a queue item is available through the authenticated administrator suspension API.
- Scheduled text Q&A with identified professionals, host answer badges and server-enforced session closing. This is not live video or a replacement for medical care. The session host is the administrator who schedules it; verify their professional credentials operationally before scheduling.
- Bounded 20-item cursor pages, database indexes, shared per-account write quotas and idempotent post/reaction requests.

Post bodies use existing AES-GCM encryption at rest. Titles, aliases and moderation metadata are not encrypted. TLS, database access controls and protected backups are still required. Moderators can review submitted community content; pseudonymity is not anonymity from the service operator. Journals, private chats and clinical records are not imported into this module or exposed to peers/guardians.

## Required before public launch

1. Use the existing production deployment with Node **22+**, PostgreSQL, HTTPS API and stable `JOURNAL_ENCRYPTION_KEY`. Keep encryption keys in a secret manager and back them up securely. The development machine currently has Node 20; tests passing there does not change the production engine requirement.
2. Run `npm run migrate` from `hercare_backend` on the deployment database. Migration `010_peer_community.sql` was applied to the local database during implementation. Do not edit applied migrations.
3. Build Flutter with `--dart-define=API_BASE_URL=https://YOUR-HOST/api/v1`. Localhost is not a deployment endpoint.
4. An authorised operator must provision a dedicated, existing `admin` account with onboarding completed. There is intentionally no public endpoint for assigning this role. Use a strong unique password, protect the account, and arrange staffing, review response targets, escalation procedures and a real support contact. All content remains pending until reviewed. Do not advertise 24/7 monitoring unless you actually provide it.
5. Publish privacy/community policies, establish report handling and retention/deletion policies, verify professional credentials and test real accounts on staging. Operational load tests, penetration testing and clinical review have not been performed by these automated checks.
6. Q&A cancellation is supported by `DELETE /api/v1/community/sessions/:id` (administrator only). Member restoration uses `PUT /api/v1/community/members/:communityMemberId/suspension` with `{ "suspended": false, "reason": "Documented reason" }`. Use authenticated operator tooling; never put admin credentials in the app package.

## Optional self-hosted AI triage

The default is multilingual rule triage **plus mandatory human review**, not a claim that an AI model is installed. No new hosted AI bill is required. Hosting, storage, CPU and human moderation can still cost money.

For the scope's AI filtering component, an optional Python adapter is implemented in `hercare_ml/app/community_moderation.py`. Deploy it separately or alongside the existing risk service with adequate CPU/RAM. Install `requirements-community.txt` in addition to the existing Python requirements. Provision a vetted multilingual zero-shot NLI model, such as [the model author's mDeBERTa MNLI/XNLI model](https://huggingface.co/MoritzLaurer/mDeBERTa-v3-base-mnli-xnli), review its license, and pin a reviewed revision. Supply tokenizer and safetensors model files in a local directory; remote custom code and request-time downloads are disabled.

Python environment:

```text
ENVIRONMENT=production
ML_SERVICE_TOKEN=<secret shared with Node>
COMMUNITY_MODEL_PATH=<absolute directory containing vetted model files>
COMMUNITY_MODEL_VERSION=<model revision and your validated policy version>
```

Node environment:

```text
COMMUNITY_MODERATION_URL=https://YOUR-PRIVATE-ML-HOST/v1/community/moderate
ML_SERVICE_TOKEN=<same secret>
```

Protect the ML endpoint with network controls and TLS. It receives submitted community text, not journals. One inference per worker is allowed at a time; Node times out after six seconds and keeps content pending if AI is missing, overloaded or returns invalid scores. Scores are triage hints, not calibrated clinical probabilities. Benchmark English, Urdu and Roman Urdu on representative reviewed examples before relying on them. The model weights have **not** been downloaded, enabled or accuracy-validated in this task.

## Verification and boundaries

- `npm run lint` and `npm test` cover backend regression and community input/triage validation.
- `RUN_COMMUNITY_DB_TEST=1 node -r dotenv/config --test test/community.integration.test.js` uses rollback-only fixtures on a migrated PostgreSQL database. It covers role restrictions, encryption, publication privacy, duplicate handling, review conflicts, blocking, pagination, deletion, suspension, Q&A and quotas.
- `flutter analyze` and `flutter test` include narrow 320×480 English/Urdu community screens, keyboard space, 1.5× text and a 280px/2× post-card test. These are automated layout checks, not a guarantee for every possible device/font combination.
- Python `python -m pytest -q` checks optional model failure, bounded inference and chunk handling without downloading model weights.

Feeds refresh on opening, explicit refresh, pull-to-refresh and completed actions; no polling, WebSocket or reply push notifications are implemented. All submissions are reviewed rather than automatically published. No fictitious members, public posts or expert sessions are seeded. No deployment or phone installation is performed as part of this implementation.
