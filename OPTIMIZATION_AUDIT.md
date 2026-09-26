# HerCare optimization audit — 2026-09-25

This is a verified optimization pass, not a certification that every device,
clinical result, or production workflow is error-free. Existing features and the
visual theme were retained. No database migrations, real clinical alerts, or
deployment changes were performed.

## Changes

- Removed HTTP payload/header logging, which could expose passwords, tokens,
  journals, and messages even during development.
- Token refresh now handles non-JSON error responses, retries a request at most
  once, closes its temporary client, and preserves sessions on transient failures.
  Only an explicit authentication rejection from the refresh endpoint clears it.
- Home tabs initialize only when first visited and retain their state afterward.
- Chat initialization/polling cannot overlap with another identical operation;
  empty/already-read polling windows no longer issue read updates.
- Reports now initially display the same weekly period they request, and tab
  listeners avoid duplicate period requests.
- Guardian invitation clipboard/post-frame callbacks check that the screen is
  still mounted.
- Fixed large-text overflow in report empty/error states, family-support options,
  consent headers, and data-rights text using wrapping/scrolling, not text scaling
  suppression.
- Mood saving stays successful if only the subsequent summary request fails.
  Concurrent mood operations keep the loading indicator accurate; an older
  journal search response cannot overwrite a newer search response.
- Guardian alert retrieval requires a currently active link, active mother
  account, and tier-2 consent, including alerts returned on the dashboard.
- Python risk-factor explanations preserve a support value of zero and no longer
  invent a limited-support factor when support data is missing. The trained
  prediction pipeline and clinical thresholds were not changed.
- Applied supported Dart static cleanups (deprecated APIs, constants, unused
  import/parameter) and migrated onboarding radios to RadioGroup.

## Verification

- Flutter analyzer: no issues (baseline: 133 findings).
- Flutter: 40 tests passed.
- Backend: 35 tests passed; ESLint passed.
- Python: 5 tests passed using the project's virtual environment.
- Android debug APK built successfully. Build warnings identify future Kotlin
  plugin migration work in firebase_core/smart_auth; no speculative dependency
  upgrades were performed during this pass.
- New layout tests: 320 x 480 logical pixels, 150% text size, English and Urdu,
  with scrolling, for login, registration, guardian invite, reports, mood,
  private journal, and all four onboarding steps.
- Existing compact-screen tests also cover screening/results, risk insights,
  secure chat, therapy hub, breathing, and memory game.
- New regression tests cover overlapping chat refresh, successful mood save with
  summary failure, guardian-alert authorization query constraints, and missing/
  zero support features.

These are fixture-based tests, not real database, Firebase delivery, speech,
Android permission, or clinical-validation tests. Layout coverage does not imply
every possible report, error message, keyboard state, or device is covered.

## Remaining release work

1. **Shared-device privacy:** feature providers currently live above authentication
   in `main.dart`. Scope their cached state and in-flight requests to the user
   session, then test logout/login between two accounts while requests are pending.
   Also clear foreground push history on logout and validate notification routing
   during cold-start authentication. Do not treat passing UI tests as verification
   of this flow.
2. **Push delivery:** test with two real devices in foreground/background/terminated
   states, denied permissions, revoked links, and network loss. Current multicast
   processing marks an outbox item sent if any device succeeds; per-device retry
   tracking is needed to retry failed devices without duplicating successful ones.
3. **Production configuration:** use the backend's declared Node >=22 runtime
   (this machine's test runtime is Node 20), deployed HTTPS API/ML endpoints,
   server-only credentials, database TLS/backups, and real Android release signing.
   The Android release configuration still uses a debug signing key.
4. **Cross-platform verification:** iOS/APNs and web push were not validated.
   Web token storage currently falls back to browser preferences; review the web
   authentication/security design before a public web deployment.
5. **Clinical limitations:** automated tests do not validate model accuracy or
   sentiment safety. Keep research-baseline/non-diagnostic wording; validate on
   representative held-out data before making clinical claims.
6. **Integration/load testing:** use an isolated test database to exercise complete
   signup/onboarding, invitation acceptance/revocation, report generation,
   screening, offline queue replay, journal uploads, and multi-device chat.
   The new alert test checks SQL authorization constraints, not live PostgreSQL
   behavior. No production traffic benchmark was performed.

Unimplemented/placeholder modules were not converted into working features by
this pass. In particular, a peer community or chatbot is separate feature work,
not an optimization of an existing implementation.
