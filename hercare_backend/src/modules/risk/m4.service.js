const db = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const { localClockMinute } = require('./recovery.service');
const { buildM4Reports } = require('./m4.score');

const FIELDS = ['financial_strain', 'relationship_strain', 'support_gap', 'recovery_difficulty'];
const LOCAL_DAY = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit',
});

function onlyKeys(body, keys) {
  if (!body || typeof body !== 'object' || Array.isArray(body)
      || Object.keys(body).some((key) => !keys.includes(key))) {
    throw new AppError('Invalid M4 request.', 422);
  }
}

function validateCheckin(body) {
  onlyKeys(body, [...FIELDS, 'date']);
  if (FIELDS.some((key) => !Object.hasOwn(body, key)
    || (body[key] !== null && (!Number.isInteger(body[key]) || body[key] < 0 || body[key] > 3)))
    || (Object.hasOwn(body, 'date') && (typeof body.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(body.date)))) {
    throw new AppError('Each context answer must be a whole number from 0 to 3 or skipped.', 422);
  }
  return FIELDS.map((key) => body[key]);
}

async function account(client, motherId) {
  const { rows } = await client.query(`
    SELECT o.age,o.months_since_birth,o.education_level,o.household_type,o.income_range,
      o.primary_support,o.delivery_method,o.parity,o.baby_gender,o.has_preeclampsia,
      o.has_postpartum_hemorrhage,o.has_preterm_birth,o.has_gestational_diabetes,o.consent_tier3
    FROM users u JOIN onboarding_data o ON o.user_id=u.id
    WHERE u.id=$1 AND u.is_active AND u.role='mother' AND u.onboarding_complete AND o.consent_tier1
    FOR SHARE OF u,o`, [motherId]);
  if (!rows.length) throw new AppError('Active mother account and basic consent required.', 403);
  return rows[0];
}

async function saveCheckin(motherId, body, now = new Date()) {
  const answers = validateCheckin(body);
  const date = LOCAL_DAY.format(now);
  if (body.date && body.date !== date) throw new AppError('The reporting day changed. Refresh and try again.', 409);
  return db.withTransaction(async (client) => {
    await account(client, motherId);
    const { rows } = await client.query(`INSERT INTO m4_context_checkins
      (mother_id,checkin_date,financial_strain,relationship_strain,support_gap,recovery_difficulty,recorded_at)
      VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(mother_id,checkin_date) DO UPDATE SET
      financial_strain=EXCLUDED.financial_strain,relationship_strain=EXCLUDED.relationship_strain,
      support_gap=EXCLUDED.support_gap,recovery_difficulty=EXCLUDED.recovery_difficulty,
      recorded_at=EXCLUDED.recorded_at
      RETURNING checkin_date::text AS date,financial_strain,relationship_strain,support_gap,recovery_difficulty`,
    [motherId, date, ...answers, now]);
    return rows[0];
  });
}

async function saveTextConsent(motherId, body) {
  onlyKeys(body, ['enabled']);
  if (typeof body.enabled !== 'boolean') throw new AppError('Choose whether to use text signals.', 422);
  return db.withTransaction(async (client) => {
    await account(client, motherId);
    await client.query(`INSERT INTO m4_text_consents(mother_id,enabled,granted_at)
      VALUES($1,$2,CASE WHEN $2 THEN clock_timestamp() ELSE NULL END)
      ON CONFLICT(mother_id) DO UPDATE SET enabled=EXCLUDED.enabled,
      granted_at=CASE WHEN NOT EXCLUDED.enabled THEN NULL
        WHEN m4_text_consents.enabled THEN m4_text_consents.granted_at ELSE clock_timestamp() END`,
    [motherId, body.enabled]);
    if (!body.enabled) await client.query('DELETE FROM m4_text_signals WHERE mother_id=$1', [motherId]);
    return { enabled: body.enabled };
  });
}

async function summary(motherId, now = new Date()) {
  const asOf = LOCAL_DAY.format(now);
  return db.withTransaction(async (client) => {
    const { consent_tier3: telemetryEnabled, ...profile } = await account(client, motherId);
    // Older clients serialize skipped answers as false/zero, indistinguishable
    // from confirmed negatives. Preserve positives and leave the rest unknown.
    profile.parity = profile.parity || null;
    for (const key of ['has_preeclampsia', 'has_postpartum_hemorrhage', 'has_preterm_birth', 'has_gestational_diabetes']) {
      profile[key] = profile[key] === true ? true : null;
    }
    const textConsent = await client.query('SELECT enabled FROM m4_text_consents WHERE mother_id=$1 FOR SHARE', [motherId]);
    const textEnabled = textConsent.rows[0]?.enabled === true;
    return readReport(client, { motherId, now, asOf, profile, telemetryEnabled, textEnabled });
  });
}

async function readReport(client, { motherId, now, asOf, profile, telemetryEnabled, textEnabled }) {
  const days = [motherId, asOf];
  const context = await client.query(`SELECT number_of_children,basic_needs_affordable,mother_in_law_relationship,
    (updated_at AT TIME ZONE 'Asia/Karachi')::date::text AS updated_date FROM risk_context WHERE mother_id=$1`, [motherId]);
  const checkins = await client.query(`SELECT checkin_date::text AS date,financial_strain,relationship_strain,
    support_gap,recovery_difficulty FROM m4_context_checkins
    WHERE mother_id=$1 AND checkin_date BETWEEN $2::date-59 AND $2::date ORDER BY checkin_date`, days);
  const moods = await client.query(`SELECT entry_date::text AS date,mood_rating,energy_level,sleep_quality,social_support
    FROM mood_checkins WHERE mother_id=$1 AND entry_date BETWEEN $2::date-59 AND $2::date ORDER BY entry_date`, days);
  const sleeps = await client.query(`SELECT sleep_date::text AS date,bedtime,wake_time,awake_minutes,quality,awakenings,
    timezone_offset_minutes,(EXTRACT(EPOCH FROM (wake_time-bedtime))/60-awake_minutes)::float AS sleep_minutes
    FROM sleep_records WHERE mother_id=$1 AND sleep_date BETWEEN $2::date-59 AND $2::date
    AND wake_time<=$3 ORDER BY sleep_date`, [...days, now]);
  const screenings = await client.query(`SELECT DISTINCT ON (instrument_type,(completed_at AT TIME ZONE 'Asia/Karachi')::date)
    (completed_at AT TIME ZONE 'Asia/Karachi')::date::text AS date,
    instrument_type AS instrument,instrument_version AS version,language,total_score AS score
    FROM screening_assessments WHERE mother_id=$1 AND status='completed'
      AND completed_at BETWEEN $2::timestamptz-INTERVAL '90 days' AND $2::timestamptz
    ORDER BY instrument_type,(completed_at AT TIME ZONE 'Asia/Karachi')::date,completed_at DESC,id DESC`, [motherId, now]);
  const safety = await client.query(`SELECT EXISTS(SELECT 1 FROM crisis_events WHERE mother_id=$1
    AND status<>'resolved' AND triggered_at<=$2)
    OR EXISTS(SELECT 1 FROM screening_assessments s WHERE s.mother_id=$1 AND s.status='completed'
      AND s.self_harm_positive AND s.completed_at BETWEEN $2::timestamptz-INTERVAL '14 days' AND $2
      AND NOT EXISTS(SELECT 1 FROM crisis_events c WHERE c.mother_id=s.mother_id
        AND c.source_type=s.instrument_type AND c.source_id=s.id AND c.triggered_at<=$2)) AS active`, [motherId, now]);
  const telemetry = telemetryEnabled ? (await client.query(`SELECT local_date::text AS date,
    usage_access,notification_access,screen_time_minutes,social_minutes,late_night_minutes,app_switches,
    notifications_seen,message_notifications,negative_notifications,distress_notifications,abuse_notifications
    FROM device_telemetry_daily WHERE mother_id=$1 AND local_date BETWEEN $2::date-60 AND $2::date ORDER BY local_date`, days)).rows : [];
  const texts = textEnabled ? (await client.query(`SELECT
    (s.recorded_at AT TIME ZONE 'Asia/Karachi')::date::text AS date,
    CASE WHEN s.journal_id IS NULL THEN 'hum_raaz' ELSE 'journal' END AS source,
    BOOL_OR(s.distress) AS distress
    FROM m4_text_signals s JOIN m4_text_consents c ON c.mother_id=s.mother_id
    WHERE s.mother_id=$1 AND c.enabled AND s.recorded_at>=c.granted_at
      AND s.recorded_at BETWEEN $2::timestamptz-INTERVAL '60 days' AND $2::timestamptz
    GROUP BY 1,2`, [motherId, now])).rows : [];
  const result = buildM4Reports({
    asOf, profile, modelContext: context.rows[0] || {}, checkins: checkins.rows, moods: moods.rows,
    screenings: screenings.rows, telemetry, texts, safetyPriority: safety.rows[0].active,
    sleeps: sleeps.rows.map(({ bedtime, wake_time, timezone_offset_minutes, ...row }) => ({
      ...row, timezone_offset_minutes, bedtime_minute: localClockMinute(bedtime, timezone_offset_minutes),
      wake_minute: localClockMinute(wake_time, timezone_offset_minutes),
    })),
  });
  return { ...result, checkin: checkins.rows.find((row) => row.date === asOf) || null, text_enabled: textEnabled };
}

module.exports = { summary, saveCheckin, saveTextConsent, validateCheckin };
