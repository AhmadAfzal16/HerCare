# Sleep and digital wellbeing connection

## Use on Android

1. Open HerCare as a mother and finish onboarding/basic monitoring consent.
2. Open **Wellbeing → Open sleep & phone usage**, or tap **Last Sleep** on Home.
3. Tap **Connect phone usage**. Read the disclosure and open Android Settings.
4. Select **HerCare → Allow usage access**, then return to HerCare. The screen
   rechecks permission and refreshes automatically. **Manage usage access** opens
   the same settings for revocation.
5. Use **Log / correct sleep** to select both bedtime and wake-up dates/times,
   using the correct dates/times. Quality, awakenings and awake-minute corrections
   are in optional details. Skipped quality/awakenings stay unknown. Save with a
   working API connection; the same-date record can be corrected later.
6. Where Android supplies a completed overnight screen-off interval of at least
   two hours, **Review and correct times** prefills a proposed interval. Review it
   before saving. It is not measured sleep and is never automatically saved.

## What the connection actually does

- Uses Android UsageStatsManager, not a private API into Google's Digital Wellbeing
  app. App-use totals are reconstructed from foreground activity events for the
  current local day, avoiding daily-bucket boundary overcounting.
- Shows today's per-app foreground minutes (top 50 apps with at least one minute),
  total app time, social-app minutes, and midnight–5am activity. Split-screen,
  launcher events, OEM retention, and missing events can differ from Android's
  own dashboard; this is not a guarantee of identical device-wide screen-on time.
- Package names/labels remain on-device. No new notification-reading permission,
  accessibility service, paid API, or always-running service is added.
- Native collection runs off the UI thread. Refresh occurs on screen open,
  return from Settings, pull-to-refresh, and the Refresh button.
- Existing risk telemetry consent/sync is unchanged. This screen does not silently
  enable tier-3 consent or upload per-app activity.
- Sleep is self-reported and saved server-side, one main sleep period per wake-up
  date. Retrying the same date replaces the record instead of creating duplicates.
  Actual sleep minutes subtract the explicitly entered awake minutes.
- Guardian reports receive average self-reported hours only, subject to tier-2
  consent and existing guardian authorization. Detailed sleep/mood insight cards
  are mother-only. Fresh recorded patterns also feed the existing M9 activities;
  unresolved crisis concerns take priority through M10.
- The screen now includes 7/14/30-calendar-day comparisons, bounded within-person
  sleep/mood associations and observed short/variable sleep patterns. It reuses
  ordinary saved check-ins, without another questionnaire. Missing/stale records
  are not filled in or described as depression/recovery. See
  `M8_IMPLEMENTATION_AND_DEPLOYMENT.md` for the exact rules and limits.
- An encrypted, account/API-bound native read cache lasts up to seven days. Offline
  copies show their saved date and are not live safety assessments. Logout and
  server access denial clear the cache. No web plaintext fallback or offline
  sleep-save queue is added. A bounded 30-second server measurement cache reduces
  repeat queries without caching authorization or current crisis state.

## Deployment

- Run backend migrations before starting the new API. Migration
  `009_sleep_records.sql` added the sleep table; NEW
  `019_optional_sleep_details.sql` makes quality/awakenings optional without
  changing existing records or any already-applied migration. Migration019 is
  applied locally; use the normal runner for each deployment database.
- Restart the Node backend after deploying the code; endpoints are authenticated
  `GET /api/v1/sleep` and `PUT /api/v1/sleep`, restricted to active mother accounts
  with tier-1 consent. Production must use HTTPS as configured by the existing app.
- No Firebase changes are required. Android usage access is approved on each
  device by its user, not granted remotely by the backend.

## Verification and boundaries

- The earlier Android connection foundation was compiled/installed on the
  development phone. That historical check does not verify the current M8 update
  or every OEM's totals. This update was tested headlessly; the app was not
  launched, built or installed, as requested.
- Added validation tests for overnight dates/timezones, malformed inputs, future
  intervals, and missing summary data.
- English/Urdu 320x480 tests cover 150% permission states and 200% trends, saved
  history, optional editor, actual save and M9/M10 navigation. They detected no
  layout overflow in these tested configurations.
- Database integration test verifies private-account reads, same-date replacement,
  aggregate guardian reports, and guardian denial using rolled-back fixtures.
  Run with `RUN_SLEEP_DB_TEST=1` and the development database environment.
- No wearable/Health Connect sleep import, sleep-stage measurement, scheduled
  bedtime alarm, offline sleep queue, continuous background sync, or iOS usage
  integration is claimed. Missing network access produces an explicit save error
  and preserves form inputs while the form remains open.
- M8 scope-core software is now implemented, including recorded pattern/trend
  analysis and sleep/mood associations. This is not automatic sleep measurement
  or a clinically validated mental-health outcome. Production device acceptance,
  clinical wording and Urdu translation review are still required.
