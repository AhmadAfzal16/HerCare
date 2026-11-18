# M10: Immediate Help and Crisis Support

Implementation and verification: **12 October 2026** (core crisis flow from 11 October; attention sound and source-checked institutional care added on 12 October). This is the emergency-support software implementation, not a clinically validated emergency service or proof that help has arrived. The app/device was not launched and no real push or test call was sent.

## Easy for the mother

- Open **Immediate help** from the existing crisis entries or the login/registration screens. Public emergency guidance and bundled contacts do not require an account or a network response.
- Calls and emergency-department search appear before longer guidance. No questionnaire, breathing timer, safety-plan completion or login blocks these actions.
- An optional area choice selects an officially sourced local emergency number. Unknown areas do not receive an invented national number; manual dialing and in-person help remain available.
- Counselling contacts, grounding and private account features expand only when needed. English/Urdu, RTL, scrolling, large text and reduced motion are supported.
- A private safety plan has just **three optional fields**: a coping step, a trusted person's name and their phone number. Quick coping choices and optional user-selected guardian prefilling reduce typing. There is no compulsory safety promise or quiz.
- The mother can explicitly download the plan to native encrypted storage for offline use. Downloaded plans are account-bound, expire after 30 days and are cleared on logout or an observed access revocation. Refresh the download periodically. Public contacts remain bundled independently.
- A connected guardian is **not** automatically treated as a safe emergency recipient. The mother makes a separate, default-off confirmation for that exact link. This is independent of saving/deleting the plan, and can be withdrawn.
- Manual support requests offer direct help and an explicit guardian-notification choice. An acknowledgement is not closure. Closing a request requires a simple outcome choice, not a new written report.

An offline phone cannot deliver a server push. HerCare never silently replays a queued offline emergency request. A timed-out online request may already have committed on the server, so the UI says delivery is unverified and advises direct help. Calls still need a working phone/carrier; external Maps needs its own connectivity.

## Scope coverage and boundaries

| Scope item | Implementation | Important boundary |
| --- | --- | --- |
| Screening activation | EPDS Q10 / PHQ-9 Q9 safety positives and configured severe screening bands create private, idempotent events | Safety-item positives are handled even with a low total; a score is not a diagnosis |
| Journal/chat activation | Existing deterministic danger cues now create event-linked urgent alerts through the M10 recipient policy | M5 now supports optional private server transcription; only a mother-reviewed/confirmed transcript enters journal safety processing, not unreviewed audio/ASR |
| HumRaaz activation | Explicit personal self-harm rules use the same M10 safe-link policy; model flags alone cannot authorize sharing | Abuse, refusal to share and infant/psychosis cues retain confidential help rather than automatic bot disclosure; cues are not clinically validated classifiers |
| ML activation | The approved clinical-model path can link a crisis event to its alert | Existing research-only baseline and untrained future forecast cannot automatically escalate a probability; no model was trained or promoted in M10 |
| Full-screen help | Responsive Immediate Help screen with optional gentle normal-breathing/grounding animation | Calling and searching never wait for the animation; completion does not infer recovery |
| Guardian / helpline calls | Sanitized direct dialer links, trusted-plan contact and Rozan/Taskeen/Umang source-labelled listings | Opening a dialer is not a connected call; availability is not guaranteed |
| Nearby care | Eight source-checked institutions in five cities, offline cards, optional city choice/local approximate-distance ranking and external Maps | Partial coverage; not a best-doctor ranking, exhaustive nearest-provider search or live-availability guarantee |
| Automatic guardian alerts | Event-linked transactional outbox with current role, consent, active link and separate safe-recipient confirmation checks | Requires configured FCM, an active guardian device and notification permission; no guaranteed delivery/response |
| Crisis records | Private timestamps, source type, acknowledgement, history and explicit resolution outcomes | Outcomes are mother-reported workflow closure, **not clinician-signed resolution, remission or medical clearance** |
| Offline plan | Optional encrypted native download, bounded size/expiry and removal | Not persisted in web localStorage; another offline device cannot instantly learn about remote revocation |

The deliberate privacy and clinical boundaries above qualify literal scope wording. Clinician-reviewed resolution and a reliable facility directory require reviewed staff/workflows/data, not fabricated medical records or fake map coordinates.

## Security and deployment architecture

The existing Flutter application calls the Node API; PostgreSQL stores encrypted plans and durable events/outbox records. There is no new hosted AI API, server-side location collection, automatic phone-call permission, media download, vector database or heavy animation engine in M10. The directory's explicit one-shot approximate location stays in phone memory; no precise/background permission is requested.

- Plan contents use AES-256-GCM with random nonces and mother-bound associated data. Configure a stable `CRISIS_ENCRYPTION_KEY` (32-byte base64 or 64-character hex), or retain the existing strong `JOURNAL_ENCRYPTION_KEY` fallback. Missing/invalid production keys fail closed. Do not rotate keys without re-encrypting stored plans and accounting for backups.
- Private endpoints require JWT authentication, mother role, active database account and basic monitoring consent. Public contacts remain available without those requirements.
- The phone sends `X-Crisis-Account-Id` for private requests. A refreshed token belonging to a different account cannot write an old screen's plan. UI generation checks and guarded dialogs/editors/history also remove stale private views on account changes.
- Bodies/fields are bounded and allowlisted; mutating endpoints have account-based rate limits. Private requests and validation failures are redacted in logs. Private crisis routes return `Cache-Control: no-store`, including authentication/conflict errors. The new public `/facilities` catalog is the deliberate exception: ETag plus five-minute public caching.
- Plan updates/deletion use optimistic versions to prevent overwriting another device. Manual requests use stable UUIDs and action fingerprints: retrying the same request returns the same event, while reusing its identifier for a different action is rejected.
- PostgreSQL enforces a separate safe-recipient confirmation at urgent-alert insertion. All new urgent sources inherit it, even if an older caller attempts an unsafe insert. A rejected alert does not prevent saving the mother's private care record.
- Alerts retain their original guardian-link identity. Replacement links, including a new link to the same guardian, cannot revive old private notices. Enabling future sharing does not retroactively disclose old source events on a stable retry.
- Both urgent in-app reads/read-marking and push delivery require the current safe link and consent. The worker also requires an unresolved owned event and expires urgent delivery eligibility after 24 hours. It rechecks again just before contacting FCM.
- Withdrawal/closure cancels pending work. Late callbacks cannot overwrite a cancelled/sent row. A final network race cannot be completely eliminated, and already delivered/retrieved notices cannot be recalled. Cancellation does not prove a previously in-flight push never arrived.
- FCM/APNs payloads contain generic support text and routing IDs, never raw journals, conversations, plan fields, phone numbers or location. Provider acceptance (`sent`) is not device delivery, guardian acknowledgement or emergency response. Urgent push retention is bounded to one hour.
- Calls allow only normalized phone numbers, not URLs, USSD or arbitrary URI schemes. Map searches use fixed HTTPS queries after user approval, with no health data or location supplied by HerCare. The external Maps application may use its own permissions and history.

## Source checking and contact maintenance

Contact sources were checked on **11 October 2026**, without calling providers or verifying current staffing. Carrier charges may apply; counselling is not emergency dispatch. The same catalog is served online and bundled offline, with a parity regression test.

- [Rozan provider page](https://rozan.org/rozan-counseling-helpline/): +92 304 111 1741; listed weekday and Ramadan hours are included in the UI.
- [Taskeen provider page](https://taskeen.org/seek-help/): +92 316 827 5336; listed Monday–Saturday hours are included.
- [Umang provider-owned listing](https://www.umang.com.pk/testimonials-page/anf/): +92 311 778 6264. Other provider pages were unavailable; the app explicitly marks current availability/hours as unconfirmed and does not show a verified 24/7 claim. Do not wait for this counselling service during an active emergency.
- Rescue 1122 coverage is scoped to the sourced areas: [Punjab](https://www.rescue.gov.pk/introduction.aspx), [Khyber Pakhtunkhwa](https://rescuekp.gov.pk/contact), [Sindh](https://sers.gos.pk/contact-us/) and [Islamabad CDA](https://www.cda.gov.pk/frequentlyAskedQuestions). No nationwide coverage guarantee is inferred.

Guidance sources: [WHO suicide Q&A](https://www.who.int/news-room/questions-and-answers/item/suicide), [NIMH adult safety-assessment guidance](https://www.nimh.nih.gov/research/research-conducted-at-nimh/asq-toolkit-materials/adult-outpatient/adult-outpatient-brief-suicide-safety-assessment-guide), [NHS postpartum psychosis](https://www.nhs.uk/mental-health/conditions/post-partum-psychosis/) and [WHO support for women subjected to violence](https://www.who.int/publications/i/item/WHO-RHR-14.26). These inform cautious help/recipient-control boundaries; they do not validate the application's detection rules.

Map connector reference: [Google Maps URLs](https://developers.google.com/maps/documentation/urls/get-started). The link-based connector needs no Maps API key. This does not make backend hosting, phone calls, clinical staffing or all project services free.

Before public release, designate a contact-review owner and periodically recheck both catalogs, clinician-review the crisis wording/thresholds, have a qualified Urdu reviewer check translations, and complete controlled two-device acceptance tests. Do not treat the source-check date as a live-availability check.

## API and project structure

The dedicated backend module is `hercare_backend/src/modules/crisis/` (routes, service, validation policy, encryption and contact catalog). Narrow existing screening/journal/chat/bot/risk/guardian/outbox changes connect their existing events to the shared privacy gate; their ordinary care features are preserved.

| Endpoint under `/api/v1/crisis` | Access / purpose |
| --- | --- |
| `GET /contacts` | Public emergency/counselling contacts |
| `GET /facilities` | Public institutional catalog; no query parameters, five-minute cache/ETag |
| `GET /support` | Mother's plan, current guardian and latest open event |
| `PUT /plan`, `DELETE /plan?version=N` | Versioned private plan changes |
| `PUT /guardian-safety` | Explicit confirmation/withdrawal for the current link |
| `POST /events` | Idempotent manual request; explicit `notify_guardian` |
| `GET /events` | Bounded, keyset-paginated private history |
| `PATCH /events/:id` | Mother's acknowledgement / explicit nonclinical closure |

Flutter uses typed crisis models/service, separate help/editor/grounding/account-guard/link/cache components and a bundled `assets/crisis_contacts.json`. The old `crisis_support_screen.dart` import remains compatible. There is no new global provider or background emergency-request queue. `url_launcher 6.3.3` is locked for external dialer/Maps links.

## Database and release steps

**Local migrations 017 and 018 were applied successfully on 11 October 2026 through the normal checksum-aware migration runner. Never edit applied SQL.** This supersedes older notes saying 017/018 were only prepared. Migration 017 adds the previously prepared research sleep-clock fields; applying it does not enable research collection/export, opt in users or backfill private records. Research flags remain off.

Migration 018 adds encrypted safety plans, manual request idempotency, acknowledgement/outcome fields and original-link/event-bound alert policy. Existing private crisis records are preserved. Old urgent alerts without the required bindings are not automatically re-shared.

For each deployment environment:

1. Back up PostgreSQL and retain encryption secrets securely. Test migration/rollback procedures in staging; do not launch an old worker against a partly upgraded release.
2. Install locked dependencies and apply **all pending migrations before updated API/worker code** (`npm run migrate` with the deployment environment). New code queries M10 columns; copying only Flutter files is insufficient.
3. Configure production HTTPS API URL, JWT/encryption secrets, approved CORS/proxy settings and the existing FCM Admin secret/token-encryption key. Never ship the Firebase Admin key or backend secrets in Flutter/source control.
4. Deploy/restart the updated backend and its existing outbox worker normally. The former `CHATBOT_GUARDIAN_ALERTS_ENABLED` prototype flag is obsolete: M10's default-off mother confirmation now authorizes eligible rule-based bot alerts. No account is confirmed automatically.
5. Build the updated Flutter application with its deployed `API_BASE_URL`; do not leave a physical production phone depending on USB `adb reverse` or localhost. iOS also needs its existing APNs provisioning.
6. On controlled staging accounts, verify permission denial/offline mode, safe confirmation, link replacement/revocation, queue failure/retry, explicit closure and notification taps on two physical devices. Check small screens, Urdu, large text, keyboards and reduced motion. Do not use actual patient danger disclosures as a release test.

The earlier plugin-symlink warning is historical; M9 subsequently resolved existing locked dependencies offline. This M10 extension adds no dependency or migration. OS settings were not changed. Standalone Kotlin compilation is not an APK/Gradle/device acceptance test, and no new APK was built or installed.

## Original 11 October verification (historical)

The following counts describe the original core implementation; current extension verification is recorded below.

## Verification performed

- **115/115 Flutter headless tests passed**, including **17 M10 tests**. Coverage includes bundled/offline fallback at 320px and 200% text in English/Urdu, safe phone/map URLs, guardian confirmation, optional plan/download/expiry/logout, stable request retries, explicit closure, account changes/open-dialog privacy and reduced motion. Scoped static analysis found no issues.
- Default backend automated suite: **73 passed, 14 opt-in suites skipped, 0 failed**. Only `test/*.test.js` was selected; the user-owned root `test-chat.js` was excluded.
- Separately enabled M10/HumRaaz/cross-module/reminder regression suite: **16 passed, 0 skipped, 0 failed**, with PostgreSQL fixtures rolled back, NLP calls disabled and notifications mocked. This includes M5/M7 event/alert idempotency, safe-link confirmation/withdrawal/replacement, in-app privacy, expiry/closure, withdrawal between both delivery checks and single screening-alert behavior.
- Changed-file Node lint and `git diff --check` passed. Existing LF/CRLF warnings and a PostgreSQL future-version warning about concurrent queries in the shared-client cross-module test fixture remain; no current test failure resulted.
- No app/device launch, persistent service/LLM daemon startup, real notification delivery, helpline test call, deployment, research export or ML training was performed.

These checks support engineering readiness; they do not prove zero bugs on all devices, medical efficacy, live emergency availability or production load/notification reliability.

## 12 October extension: attention sound and institutional directory

The existing safe-link/consent/event checks remain mandatory. No real account was opted in, no model promoted, no research collection enabled, and no migration was added or edited. Local migrations 001–020 remain applied.

### Attention and guardian notification sounds

An optional collapsed section in Immediate Help contains an explicitly started local attention chime with Stop. Its total deadline is fifteen seconds including initialization. It stops on hiding/backgrounding, account replacement, disposal, audio-focus interruption and disconnecting headphones; it does not request guardian help or infer safety. Shared audio-focus leases prevent a stale meditation/alarm instance releasing a newer lease.

Two original standard-library-generated mono PCM assets total **332,888 bytes**: an eight-second phone chime and a 2.4-second native Android notification sound. Reproduce them with `hercare_ml/scripts/crisis_audio.py`; headless tests check PCM format, bounded amplitude, duration and deterministic hashes. No runtime synthesis or audio API key is needed.

Only `crisis` / `risk_severe` guardian pushes set `urgent: "true"`, high priority, `hercare_urgent_v1` and `hercare_urgent` sound. Ordinary updates and screening reminders keep their existing channels. A generic foreground Android notification uses the same urgent channel; it requires the exact signed-in guardian, deduplicates bounded identifiers and validates taps before routing. iOS background APNs uses the existing default sound; **no custom iOS foreground alarm or critical-alert entitlement was implemented**.

Android notification channels remain controlled by the user; permission denial, mute, channel settings and Do Not Disturb may prevent sound. The updated Android app must be opened normally at least once to create the new channel. Older installed versions do not contain the new sound resource. Never use the sound as proof of delivery or emergency response. See [Firebase Android notification setup](https://firebase.google.com/docs/cloud-messaging/android/get-started).

Device registration is serialized across logout, stale token results are discarded, and register/unregister requests send `X-Notification-Account-Id`; the API rejects account mismatches with 409 before controllers. Notification routes are no-store, and CORS permits the account header.

### Low-input directory and location privacy

The directory is public: login, questionnaires, address entry and location permission are not required. One optional city choice filters cards. A separate, confirmed approximate-location button requests one foreground fix; denial/offline/unsupported devices retain city choice, phone numbers and Maps. Native Android requests **only ACCESS_COARSE_LOCATION**, iOS defaults to reduced accuracy/When In Use. Both bound acquisition to ten seconds, validate actual fix age/accuracy, quantize to 0.01 degrees and never retain/send coordinates. Permission waits are bounded separately. Older Android uses only a sufficiently fresh existing fix, not a continuous listener. This follows foreground/approximate access boundaries in [Android permissions guidance](https://developer.android.com/develop/sensors-and-location/location/permissions) and the one-shot [Apple requestLocation API](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()).

The directory forgets its fix on background/exit/explicit removal or after five minutes; a late response cannot restore a cleared fix. Transient inactive state caused by the permission prompt is not mistaken for backgrounding. Approximate straight-line distances rank **listed published points only**, not all nearby doctors, road distance or travel time. Entries with no checked coordinates receive no invented distance. AKU publishes a geo point; PIMH, PIMS and Mayo publish map-view centres, which are explicitly not surveyed entrances. Directions use a fixed public institution/address Maps query, not the app's location or clinical data; Maps/source pages need confirmation and have their own privacy policies.

Institution sources checked on **12 October 2026**, with catalog review due **10 January 2027**:

- Lahore: [PIMH contact/exchange](https://pimh.punjab.gov.pk/contact_us) and [Mayo Hospital](https://www.mayohospital.gop.pk/), with their separately linked psychiatry/emergency pages.
- Islamabad: [PIMS contact/exchange](https://pims.gov.pk/contactus.php), [psychiatry](https://www.pims.gov.pk/Psychiatry.php) and [published map](https://pims.gov.pk/location.php).
- Karachi: [JPMC institutional listing](https://www.jpmc.edu.pk/) and [AKU main campus/contact/services](https://hospitals.aku.edu/pakistan/facility/akuh-main-campus).
- Peshawar: [KTH contact](https://kth.edu.pk/contact-us/) / [psychiatry](https://kth.edu.pk/psychiatry/) and [LRH emergency services](https://www.lrh.edu.pk/services/emergency-services.html). LRH is labelled general emergency assessment; this listing does not verify a dedicated psychiatric emergency team.
- Quetta: [BIPBS published psychiatric OPD information](https://bipbs.gob.pk/?page_id=1906). It names multiple hospital venues; the entry requires confirmation with the institute rather than inventing a single location.

Some institutional sites returned access/server errors during direct retrieval; their indexed primary pages were consulted. No calls, individual doctor credential verification, staff availability, fees or live appointments were tested. The eight entries are not comprehensive nationwide coverage or clinically approved referrals. Calls are hospital/institute contacts, not guaranteed direct clinician lines.

The exact catalog is bundled at `assets/care_facilities.json` and served from backend `src/modules/crisis/facilities.json`, with automated parity verification. Fixed approved institutional hosts, exact public fields, bounded schema, review dates and coordinate provenance reject unsafe data. Unknown/private fields are rejected before caching and malformed/poisoned old cache entries are removed. Review intervals are capped at 180 days; the complete UTC due day remains current, while future checks are explicitly unconfirmed. Downloads use an unauthenticated public client, bounded streaming body and origin-bound public cache (six-hour refresh, seven-day expiry); no city, coordinates, account, journals or scores are stored there. Refresh is coalesced. Expired/future checks produce warnings, not silent removal of usable phone details.

The backend accepts **no query parameters**, including parser-discarded prototype-shaped input, and caps catalog size/count. Request/error URL logging drops query values; referrers are not logged. Public response bytes have a SHA256 ETag and a five-minute cache, while all private crisis endpoints stay no-store.

### Operator release gate and acceptance

Run `node src/modules/crisis/crisis.directory.js --check` before releasing a catalog. Recheck official phone/service/location sources, preserve coordinate-kind honesty, update both JSON copies and review dates, and redeploy/restart the API (validated catalog is held in-process). Adding a new source host requires reviewing and changing both code-owned allowlists. Never accept an unreviewed doctor URL or fabricate a location.

Before release, controlled two-phone tests must cover Android foreground/background/terminated notifications and taps, updated-app first-open/channel creation, denied permission, DND/mute, logout/account switch, invalid tokens, safe-link withdrawal/replacement and offline behavior. Test location denial/services off/timeout/cancellation and approximate distance caveats on physical Android/iOS devices. iOS needs a macOS build and APNs provisioning. Listen to sounds at comfortable levels and review Urdu/clinical wording. Do not test using real patient emergencies. No app launch, APK build/install, real push/call/Maps opening or real location prompt was performed here.

Current extension engineering verification: full Flutter **269 tests passed** (22 directory, 13 alarm/notification-bridge, 18 core crisis tests), Python **161 tests passed**, full Flutter analysis clean; backend default suite **104 passed, 16 opt-in skipped, 0 failed**, and full backend lint passed. Separately enabled M10 PostgreSQL synthetic rollback/fake-push checks passed (five tests across the core and M5/M7 suites). All five actual Kotlin sources compiled standalone against existing Kotlin 2.2.20/JVM17/Android36/Flutter jars; no Gradle/APK build. iOS plist/static lifecycle checks passed but UIKit/CoreLocation compilation cannot be verified on this Windows host. Python reported existing Starlette/sklearn dependency deprecation/solver warnings without test failures; native compilation reported API-guarded notification/JDK deprecation warnings. Clinical efficacy, device delivery, zero bugs and production performance are not established by these checks.
