const { query } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const client = require('./risk.client');
const { validateRecoveryResponse } = require('./recovery.response');

function dateString(value) {
  return typeof value === 'string' ? value.slice(0, 10) : value.toISOString().slice(0, 10);
}
function localClockMinute(value, timezoneOffsetMinutes) {
  const shifted = new Date(new Date(value).getTime() - Number(timezoneOffsetMinutes) * 60000);
  if (!Number.isFinite(shifted.getTime())) throw new AppError('Stored sleep timing is unavailable.', 503);
  return shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
}
async function summary(motherId, now = new Date()) {
  const account = await query(`SELECT u.id FROM users u JOIN onboarding_data o ON o.user_id=u.id
    WHERE u.id=$1 AND u.is_active AND u.role='mother' AND o.consent_tier1`, [motherId]);
  if (!account.rows.length) throw new AppError('Active mother account and basic consent required.', 403);
  const asOf = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  const [moods, screens, sleep] = await Promise.all([
    query(`SELECT entry_date::text,mood_rating,energy_level,sleep_quality,social_support FROM mood_checkins
      WHERE mother_id=$1 AND entry_date BETWEEN $2::date-59 AND $2::date ORDER BY entry_date LIMIT 60`, [motherId, asOf]),
    // Latest completed assessment per instrument/local day prevents same-day
    // repeats from manufacturing a follow-up interval. Preserve version/language.
    query(`SELECT * FROM (SELECT DISTINCT ON (instrument_type,(completed_at AT TIME ZONE 'Asia/Karachi')::date)
        instrument_type,instrument_version,language,total_score,self_harm_positive,completed_at,
        BOOL_OR(self_harm_positive) OVER (PARTITION BY instrument_type,(completed_at AT TIME ZONE 'Asia/Karachi')::date) AS safety_positive_in_day,
        COUNT(*) FILTER (WHERE self_harm_positive) OVER () AS safety_positive_count,
        MAX(completed_at) FILTER (WHERE self_harm_positive) OVER () AS last_safety_positive_at
      FROM screening_assessments WHERE mother_id=$1 AND status='completed' AND completed_at<=$2
        AND completed_at>=$2::timestamptz-INTERVAL '90 days'
      ORDER BY instrument_type,(completed_at AT TIME ZONE 'Asia/Karachi')::date,completed_at DESC,id DESC) daily
      ORDER BY completed_at DESC LIMIT 120`, [motherId, now]),
    query(`SELECT sleep_date::text,bedtime,wake_time,awake_minutes,quality,awakenings,timezone_offset_minutes,
        EXTRACT(EPOCH FROM (wake_time-bedtime))/60-awake_minutes AS sleep_minutes
      FROM sleep_records WHERE mother_id=$1 AND sleep_date BETWEEN $2::date-59 AND $2::date
        AND wake_time<=$3 ORDER BY sleep_date LIMIT 60`, [motherId, asOf, now]),
  ]);
  const number = (value) => value == null ? null : Number(value);
  const localDay = (value) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(value));
  const result = await client.request('/v1/recovery', {
    as_of: asOf,
    observations: moods.rows.map((row) => ({ entry_date: dateString(row.entry_date), mood_rating: number(row.mood_rating),
      energy_level: number(row.energy_level), sleep_quality: number(row.sleep_quality), social_support: number(row.social_support) })),
    screenings: screens.rows.map((row) => ({ instrument: row.instrument_type, version: row.instrument_version,
      language: row.language, score: number(row.total_score), safety_positive: row.self_harm_positive,
      safety_positive_in_day: row.safety_positive_in_day,
      completed_date: localDay(row.completed_at) })),
    screening_safety_history: screens.rows.length ? {
      recorded_positive_count: number(screens.rows[0].safety_positive_count),
      latest_positive_date: screens.rows[0].last_safety_positive_at ? localDay(screens.rows[0].last_safety_positive_at) : null,
    } : undefined,
    sleep_observations: sleep.rows.map((row) => ({ entry_date: dateString(row.sleep_date), sleep_minutes: number(row.sleep_minutes),
      awake_minutes: number(row.awake_minutes), awakenings: number(row.awakenings), quality: number(row.quality),
      bedtime_minute: localClockMinute(row.bedtime, row.timezone_offset_minutes),
      wake_minute: localClockMinute(row.wake_time, row.timezone_offset_minutes) })),
  });
  // Consent/account withdrawal while the private model runs must not publish a
  // just-computed private aggregate. This does not collect research or alert anyone.
  const current = await query(`SELECT u.id FROM users u JOIN onboarding_data o ON o.user_id=u.id
    WHERE u.id=$1 AND u.is_active AND u.role='mother' AND o.consent_tier1`, [motherId]);
  if (!current.rows.length) throw new AppError('Active mother account and basic consent required.', 403);
  return validateRecoveryResponse(result);
}
module.exports = { summary, dateString, localClockMinute };
