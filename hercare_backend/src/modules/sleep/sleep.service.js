const db = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const { _private: { periodBounds } } = require('../mood/mood.service');
const { validateSleep, dashboardQuery } = require('./sleep.logic');
const { buildInsights } = require('./sleep.insights');
const snapshots = new Map();
const CACHE_MS = 30000;
function invalidate(motherId) {
  for (const key of snapshots.keys()) if (key.startsWith(`${motherId}:`)) snapshots.delete(key);
}

async function authorize(client, motherId) {
  const result = await client.query(`SELECT od.consent_tier2,od.consent_tier3 FROM users u
    JOIN onboarding_data od ON od.user_id=u.id WHERE u.id=$1 AND u.role='mother' AND u.is_active AND od.consent_tier1
    FOR SHARE OF u,od`, [motherId]);
  if (!result.rows[0]) throw new AppError('Active mother account and basic monitoring consent required.', 403);
  return result.rows[0];
}
async function dashboard(motherId, query) {
  const { asOf } = dashboardQuery(query);
  return db.withTransaction(async (client) => {
    const consent = await authorize(client, motherId);
    const key = `${motherId}:${asOf}:${consent.consent_tier3 === true}`;
    let snapshot = snapshots.get(key);
    if (!snapshot || snapshot.expires <= Date.now()) {
      const sleep = await client.query(`SELECT sleep_date::text,bedtime,wake_time,awake_minutes,quality,awakenings,
      timezone_offset_minutes,EXTRACT(EPOCH FROM(wake_time-bedtime))/60-awake_minutes AS sleep_minutes
      FROM sleep_records WHERE mother_id=$1 AND sleep_date BETWEEN $2::date-59 AND $2::date ORDER BY sleep_date DESC LIMIT 60`, [motherId, asOf]);
      const moods = await client.query(`SELECT entry_date::text,mood_rating FROM mood_checkins
      WHERE mother_id=$1 AND entry_date BETWEEN $2::date-29 AND $2::date ORDER BY entry_date DESC LIMIT 30`, [motherId, asOf]);
      const telemetry = consent.consent_tier3 ? await client.query(`SELECT local_date::text,usage_access,screen_time_minutes,social_minutes,late_night_minutes
      FROM device_telemetry_daily WHERE mother_id=$1 AND local_date BETWEEN $2::date-6 AND $2::date ORDER BY local_date DESC LIMIT 7`, [motherId, asOf]) : { rows: [] };
      snapshot = { sleep: sleep.rows, moods: moods.rows, telemetry: telemetry.rows, expires: Date.now() + CACHE_MS };
      snapshots.delete(key);
      snapshots.set(key, snapshot);
      while (snapshots.size > 100) snapshots.delete(snapshots.keys().next().value);
    }
    // Roles/consent above and current safety below are NEVER supplied by cache.
    const safety = await client.query(`SELECT EXISTS(SELECT 1 FROM crisis_events WHERE mother_id=$1 AND status<>'resolved') AS needs_help`, [motherId]);
    const insights = buildInsights({ sleep: snapshot.sleep, moods: snapshot.moods, telemetry: snapshot.telemetry, asOf,
      safetyPriority: safety.rows[0]?.needs_help === true, telemetryConsent: consent.consent_tier3 === true });
    return { records: snapshot.sleep.slice(0, 30), summary: { recorded_nights: insights.windows[0].current.nights,
      average_minutes: insights.windows[0].current.average_minutes, source: 'self_reported', window_days: 7 }, insights };
  });
}
async function save(motherId, body) {
  const data = validateSleep(body);
  const result = await db.withTransaction(async (client) => {
    await client.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [motherId]);
    const consent = await authorize(client, motherId);
    await client.query(`INSERT INTO sleep_records(mother_id,sleep_date,bedtime,wake_time,awake_minutes,quality,awakenings,timezone_offset_minutes)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(mother_id,sleep_date) DO UPDATE SET bedtime=EXCLUDED.bedtime,
      wake_time=EXCLUDED.wake_time,awake_minutes=EXCLUDED.awake_minutes,quality=EXCLUDED.quality,
      awakenings=EXCLUDED.awakenings,timezone_offset_minutes=EXCLUDED.timezone_offset_minutes,updated_at=NOW()`,
    [motherId, data.sleep_date, data.bedtime, data.wake_time, data.awake_minutes, data.quality, data.awakenings, data.timezone_offset_minutes]);
    if (consent.consent_tier2) for (const type of ['daily', 'weekly', 'monthly']) {
      const bounds = periodBounds(type, data.sleep_date);
      await client.query(`INSERT INTO health_reports(mother_id,period_type,period_start,period_end,sleep_avg_h,report_data)
        SELECT $1,$2,$3::date,$4::date,ROUND(AVG(EXTRACT(EPOCH FROM(wake_time-bedtime))/3600-awake_minutes/60.0),2),
          jsonb_build_object('status','available','sleep_source','self_reported','sleep_nights',COUNT(*)) FROM sleep_records
          WHERE mother_id=$1 AND sleep_date BETWEEN $3::date AND $4::date
        ON CONFLICT(mother_id,period_type,period_start,period_end) DO UPDATE SET sleep_avg_h=EXCLUDED.sleep_avg_h,
          report_data=health_reports.report_data||EXCLUDED.report_data,updated_at=NOW()`, [motherId, type, bounds.start, bounds.end]);
    }
    return { saved: true };
  });
  invalidate(motherId);
  return result;
}
module.exports = { dashboard, save, invalidate };
