# Sleep and digital wellbeing connection

## Use on Android

1. Open HerCare as a mother and finish onboarding/basic monitoring consent.
2. Open **Wellbeing → Open sleep & phone usage**, or tap **Last Sleep** on Home.
3. Tap **Connect phone usage**. Read the disclosure and open Android Settings.
4. Select **HerCare → Allow usage access**, then return to HerCare. The screen
   rechecks permission and refreshes automatically. **Manage usage access** opens
   the same settings for revocation.
5. Use **Log / correct sleep** to select both bedtime and wake-up dates/times,
   minutes awake, awakenings, and sleep quality. Save with a working API connection.
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
  consent and existing guardian authorization. Recent recorded sleep quality
  also feeds the therapy recommendation service.

## Deployment

- Run backend migrations before starting the new API. Migration
  `009_sleep_records.sql` adds the sleep table without changing applied migrations.
- Restart the Node backend after deploying the code; endpoints are authenticated
  `GET /api/v1/sleep` and `PUT /api/v1/sleep`, restricted to active mother accounts
  with tier-1 consent. Production must use HTTPS as configured by the existing app.
- No Firebase changes are required. Android usage access is approved on each
  device by its user, not granted remotely by the backend.

## Verification and boundaries

- Android debug APK compiled and installed on the connected development phone.
  Android reported HerCare usage access as allowed. This does not itself prove
  every OEM's event totals match its Digital Wellbeing app.
- Added validation tests for overnight dates/timezones, malformed inputs, future
  intervals, and missing summary data.
- Added English/Urdu 320x480, 150%-text layout tests for permission-denied and
  permission-granted states, sleep form navigation, and invalid save handling.
- Database integration test verifies private-account reads, same-date replacement,
  aggregate guardian reports, and guardian denial using rolled-back fixtures.
  Run with `RUN_SLEEP_DB_TEST=1` and the development database environment.
- No wearable/Health Connect sleep import, sleep-stage measurement, scheduled
  bedtime alarm, offline sleep queue, continuous background sync, or iOS usage
  integration is claimed. Missing network access produces an explicit save error
  and preserves form inputs while the form remains open.
- This completes the requested Android connection and sleep recording foundation,
  not every M8 scope item: longitudinal sleep/mood correlations and worsening-trend
  analysis remain separate work. Do not infer a diagnosis from phone usage or
  estimated inactivity.
