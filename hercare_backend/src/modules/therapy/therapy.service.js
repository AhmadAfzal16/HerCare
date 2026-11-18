const database = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const { buildInsights } = require('../sleep/sleep.insights');
const { normalizeSession, MEASURE_KEYS } = require('./therapy.validator');
const { isKnownActivity } = require('./therapy.catalog');

const query = (...args) => database.query(...args);
const SUMMARY_DAYS = 30;

function publicSession(row) {
  return {
    id: row.id,
    activity_type: row.activity_type,
    activity_id: row.activity_id,
    duration_seconds: row.duration_seconds,
    mood_before: row.mood_before,
    mood_after: row.mood_after,
    mood_change: row.completed && row.mood_before != null && row.mood_after != null
      ? row.mood_after - row.mood_before : null,
    completed: row.completed,
    breathing_participation: row.breathing_participation ?? null,
    completed_at: row.completed_at,
    practice_verified: false,
    measures: publicMeasures(row),
  };
}
// Only what was recorded; changes are computed for display, not stored.
function publicMeasures(row) {
  const measures = Object.fromEntries(MEASURE_KEYS.filter((key) => row[key] != null).map((key) => [key, row[key]]));
  if (!Object.keys(measures).length) return null;
  const change = (before, after) => (row[before] != null && row[after] != null ? row[after] - row[before] : null);
  return { ...measures, tension_change: change('tension_before', 'tension_after'), hr_change: change('hr_before', 'hr_after'),
    hrv_change: change('hrv_before', 'hrv_after') };
}

async function assertMother(userId, role, connection = database, lock = false) {
  if (role !== 'mother') throw new AppError('Therapeutic activities are available to mother accounts.', 403);
  const result = await connection.query(
    `SELECT u.is_active, od.consent_tier1 FROM users u
     JOIN onboarding_data od ON od.user_id = u.id
     WHERE u.id = $1 AND u.role = 'mother'${lock ? ' FOR SHARE OF u, od' : ''}`, [userId],
  );
  if (!result.rows[0]?.is_active || result.rows[0].consent_tier1 !== true) {
    throw new AppError('Your account and basic consent must be active to use private activity records.', 403);
  }
}

async function recordSession(userId, role, data) {
  const payload = normalizeSession(data);
  return database.withTransaction(async (connection) => {
    await assertMother(userId, role, connection, true);
    const { rows } = await connection.query(
      `INSERT INTO therapeutic_sessions
         (mother_id, activity_type, activity_id, duration_seconds, mood_before,
          mood_after, completed, client_request_id, completed_at, breathing_participation,
          ${MEASURE_KEYS.join(', ')})
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,COALESCE($9::timestamptz,NOW()),$10,
          ${MEASURE_KEYS.map((_, index) => `$${index + 11}`).join(',')})
       ON CONFLICT (mother_id, client_request_id) DO NOTHING
       RETURNING *`,
      [userId, payload.activity_type, payload.activity_id, payload.duration_seconds,
        payload.mood_before, payload.mood_after, payload.completed, payload.client_request_id,
        payload.client_completed_at ?? null, payload.breathing_participation ?? null,
        ...MEASURE_KEYS.map((key) => payload[key] ?? null)],
    );
    if (rows[0]) return publicSession(rows[0]);
    const previous = await connection.query(
      `SELECT * FROM therapeutic_sessions WHERE mother_id = $1
       AND client_request_id = $2 FOR SHARE`, [userId, payload.client_request_id],
    );
    const row = previous.rows[0];
    if (!row || (row.breathing_participation ?? null) !== (payload.breathing_participation ?? null)
      || MEASURE_KEYS.some((key) => (row[key] ?? null) !== (payload[key] ?? null))
      || Object.keys(payload).some((key) => key === 'client_completed_at'
      ? new Date(row.completed_at).getTime() !== Date.parse(payload[key]) : row[key] !== payload[key])) {
      throw new AppError('This activity request was already saved with different details.', 409);
    }
    return publicSession(row);
  });
}

async function getHistory(userId, role, limit = 30) {
  await assertMother(userId, role);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new AppError('History limit must be between 1 and 100.', 422);
  }
  const { rows } = await query(
    `SELECT * FROM therapeutic_sessions WHERE mother_id = $1
     ORDER BY completed_at DESC, id DESC LIMIT $2`,
    [userId, limit],
  );
  return rows.map(publicSession);
}

function chooseRecommendation(signals) {
  if (signals.safetyPriority) {
    return {
      activity_type: 'breathing', activity_id: 'cyclic_sighing',
      reason: 'Use a brief calming exercise while opening immediate safety support.',
      reason_ur: 'فوری حفاظتی مدد کھولتے ہوئے مختصر پرسکون سانس کی مشق کریں۔',
      safety_priority: true,
    };
  }
  if (signals.mood !== null && signals.mood <= 2) {
    return {
      activity_type: 'cbt', activity_id: 'grounding_54321',
      reason: 'A grounding exercise may help when today feels emotionally heavy.',
      reason_ur: 'جب آج کا دن جذباتی طور پر بھاری لگے تو گراؤنڈنگ مشق مدد کر سکتی ہے۔',
      safety_priority: false,
    };
  }
  // A practice felt distressing in the last week: eyes-open, shorter options before inward-focused ones.
  if (signals.recentDistress) {
    return {
      activity_type: 'cbt', activity_id: 'grounding_54321',
      reason: 'A recent practice felt uncomfortable, so a short eyes-open grounding exercise is suggested first.',
      reason_ur: 'حالیہ مشق میں بے آرامی محسوس ہوئی، اس لیے پہلے آنکھیں کھلی رکھ کر مختصر گراؤنڈنگ مشق تجویز ہے۔',
      safety_priority: false,
    };
  }
  if (signals.sleepPatternNeedsRest || (signals.sleepQuality !== null && signals.sleepQuality <= 2)
      || signals.lateNightMinutes >= 30) {
    return {
      activity_type: 'meditation', activity_id: 'body_scan',
      reason: 'Your recent sleep pattern suggests a short body-scan wind-down.',
      reason_ur: 'حالیہ نیند کے انداز کے مطابق مختصر باڈی اسکین مفید ہو سکتا ہے۔',
      safety_priority: false,
    };
  }
  if (signals.screenMinutes >= 300) {
    return {
      activity_type: 'game', activity_id: 'color_calm',
      reason: 'A two-minute low-stimulation color activity offers a gentle screen reset.',
      reason_ur: 'دو منٹ کی ہلکی رنگوں کی سرگرمی اسکرین سے نرم وقفہ دیتی ہے۔',
      safety_priority: false,
    };
  }
  return {
    activity_type: 'breathing', activity_id: 'cyclic_sighing',
    reason: 'Five minutes of exhale-focused breathing a day is a gentle reset.',
    reason_ur: 'روزانہ پانچ منٹ لمبی سانس چھوڑنے والی مشق ایک نرم سکون ہے۔',
    safety_priority: false,
  };
}

function rankRecommendation(signals, history = [], recentActivity = null) {
  const context = chooseRecommendation(signals);
  const metadata = { rule_version: 'm9-context-paired-ratings-v1',
    selection_source: 'recent_context_rules', clinical_improvement: false };
  // Safety support and low-mood grounding never depend on optional practice ratings.
  if (context.safety_priority || (signals.mood !== null && signals.mood <= 2) || signals.recentDistress) {
    return { ...context, ...metadata };
  }
  const candidates = history.map((row) => ({
    activity_type: row.activity_type, activity_id: row.activity_id,
    paired_mood_sessions: Number(row.paired_mood_sessions), avg_mood_change: Number(row.avg_mood_change),
  })).filter((row) => row.activity_type === context.activity_type
    && isKnownActivity(row.activity_type, row.activity_id)
    && Number.isInteger(row.paired_mood_sessions) && row.paired_mood_sessions >= 3
    && Number.isFinite(row.avg_mood_change) && row.avg_mood_change > 0 && row.avg_mood_change <= 4);
  candidates.sort((a, b) => b.avg_mood_change - a.avg_mood_change
    || Number(a.activity_id === recentActivity) - Number(b.activity_id === recentActivity)
    || b.paired_mood_sessions - a.paired_mood_sessions
    || a.activity_id.localeCompare(b.activity_id));
  if (!candidates.length) return { ...context, ...metadata };
  const selected = candidates[0];
  return {
    ...context, ...metadata, activity_id: selected.activity_id,
    reason: 'Your optional before-and-after practice ratings were higher on average after this activity. This is a personal observation, not proof of treatment benefit.',
    reason_ur: 'اس سرگرمی کے بعد آپ کی اختیاری مزاج کی ریٹنگ اوسطاً پہلے سے زیادہ تھی۔ یہ ذاتی مشاہدہ ہے، علاج کے فائدے کا ثبوت نہیں۔',
    selection_source: 'optional_paired_practice_ratings',
    history_observation: { ...selected, period_days: SUMMARY_DAYS, minimum_pairs: 3,
      measurement: 'optional_self_reported_immediate_mood_change', practice_verified: false },
  };
}

async function getRecommendation(userId, role) {
  await assertMother(userId, role);
  const [moodResult, telemetryResult, screeningResult, recentResult, sleepResult, crisisResult, practiceResult, distressResult] = await Promise.all([
    query(`SELECT mood_rating, sleep_quality FROM mood_checkins
           WHERE mother_id = $1 AND entry_date BETWEEN CURRENT_DATE - 2 AND CURRENT_DATE ORDER BY entry_date DESC LIMIT 1`, [userId]),
    query(`SELECT t.screen_time_minutes,t.late_night_minutes FROM device_telemetry_daily t
           JOIN onboarding_data od ON od.user_id=t.mother_id AND od.consent_tier3
           WHERE t.mother_id=$1 AND t.usage_access AND t.local_date BETWEEN CURRENT_DATE-2 AND CURRENT_DATE ORDER BY t.local_date DESC LIMIT 1`, [userId]),
    query(`SELECT self_harm_positive FROM screening_assessments
           WHERE mother_id = $1 AND status='completed' ORDER BY completed_at DESC LIMIT 1`, [userId]),
    query(`SELECT activity_id FROM therapeutic_sessions WHERE mother_id = $1
           AND completed = TRUE AND completed_at >= NOW() - INTERVAL '30 days'
           ORDER BY completed_at DESC, id DESC LIMIT 1`, [userId]),
    query(`SELECT sleep_date::text,quality,awakenings,bedtime,wake_time,timezone_offset_minutes,
             EXTRACT(EPOCH FROM(wake_time-bedtime))/60-awake_minutes AS sleep_minutes FROM sleep_records WHERE mother_id=$1
             AND sleep_date>=CURRENT_DATE-59 AND sleep_date<=CURRENT_DATE ORDER BY sleep_date DESC LIMIT 60`, [userId]),
    query(`SELECT EXISTS(SELECT 1 FROM crisis_events WHERE mother_id=$1 AND status<>'resolved') AS needs_help`, [userId]),
    query(`SELECT activity_type, activity_id, COUNT(*) AS paired_mood_sessions,
             AVG(mood_after-mood_before) AS avg_mood_change FROM therapeutic_sessions
           WHERE mother_id=$1 AND completed=TRUE AND mood_before IS NOT NULL AND mood_after IS NOT NULL
             AND completed_at>=NOW()-INTERVAL '30 days' AND completed_at<=NOW()
           GROUP BY activity_type,activity_id HAVING COUNT(*)>=3 AND AVG(mood_after-mood_before)>0
           ORDER BY AVG(mood_after-mood_before) DESC,COUNT(*) DESC,activity_id LIMIT 14`, [userId]),
    query(`SELECT EXISTS(SELECT 1 FROM therapeutic_sessions WHERE mother_id=$1 AND distress_reported
             AND completed_at>=NOW()-INTERVAL '7 days') AS recent_distress`, [userId]),
  ]);
  const mood = moodResult.rows[0];
  const telemetry = telemetryResult.rows[0];
  const sleep = buildInsights({ sleep: sleepResult.rows, asOf: new Date().toISOString().slice(0, 10) });
  const signals = {
    mood: mood?.mood_rating ?? null,
    sleepQuality: !sleep.stale ? sleepResult.rows[0]?.quality ?? mood?.sleep_quality ?? null : mood?.sleep_quality ?? null,
    sleepPatternNeedsRest: sleep.patterns.includes('repeated_short_sleep') || sleep.patterns.includes('less_sleep_than_previous_period'),
    screenMinutes: telemetry?.screen_time_minutes ?? 0,
    lateNightMinutes: telemetry?.late_night_minutes ?? 0,
    safetyPriority: crisisResult.rows[0]?.needs_help === true || screeningResult.rows[0]?.self_harm_positive === true,
    recentDistress: distressResult.rows[0]?.recent_distress === true,
  };
  const recommendation = rankRecommendation(signals, practiceResult.rows, recentResult.rows[0]?.activity_id);
  return { ...recommendation, generated_at: new Date().toISOString() };
}

async function getSummary(userId, role) {
  await assertMother(userId, role);
  const { rows } = await query(
    `SELECT COUNT(*) AS total_sessions,
            COUNT(*) FILTER (WHERE completed = TRUE) AS completed_sessions,
            COALESCE(SUM(duration_seconds) FILTER (WHERE completed = TRUE), 0) AS total_seconds,
            COUNT(*) FILTER (WHERE completed = TRUE AND mood_before IS NOT NULL
              AND mood_after IS NOT NULL) AS paired_mood_sessions,
            ROUND(AVG(mood_after - mood_before) FILTER
              (WHERE completed = TRUE AND mood_before IS NOT NULL AND mood_after IS NOT NULL), 2) AS avg_mood_change,
            COUNT(*) FILTER (WHERE tension_before IS NOT NULL AND tension_after IS NOT NULL) AS paired_tension_sessions,
            ROUND(AVG(tension_after - tension_before), 2) AS avg_tension_change,
            COUNT(*) FILTER (WHERE hr_before IS NOT NULL AND hr_after IS NOT NULL) AS paired_heart_sessions,
            ROUND(AVG(hr_after - hr_before), 1) AS avg_hr_change,
            COUNT(*) FILTER (WHERE hrv_before IS NOT NULL AND hrv_after IS NOT NULL) AS paired_hrv_sessions,
            ROUND(AVG(hrv_after - hrv_before), 1) AS avg_hrv_change,
            COUNT(*) FILTER (WHERE distress_reported) AS distress_sessions
     FROM therapeutic_sessions WHERE mother_id = $1
       AND completed_at >= NOW() - INTERVAL '30 days' AND completed_at <= NOW()`,
    [userId],
  );
  const row = rows[0];
  return {
    total_sessions: Number(row.total_sessions),
    completed_sessions: Number(row.completed_sessions),
    total_seconds: Number(row.total_seconds),
    paired_mood_sessions: Number(row.paired_mood_sessions),
    avg_mood_change: row.avg_mood_change === null ? null : Number(row.avg_mood_change),
    period_days: SUMMARY_DAYS,
    // Changes are after minus before. Heart readings are approximate (camera) or band-based,
    // and describe relaxation during practice, not a diagnosis or treatment effect.
    monitoring: {
      paired_tension_sessions: Number(row.paired_tension_sessions ?? 0),
      avg_tension_change: row.avg_tension_change == null ? null : Number(row.avg_tension_change),
      paired_heart_sessions: Number(row.paired_heart_sessions ?? 0),
      avg_hr_change: row.avg_hr_change == null ? null : Number(row.avg_hr_change),
      paired_hrv_sessions: Number(row.paired_hrv_sessions ?? 0),
      avg_hrv_change: row.avg_hrv_change == null ? null : Number(row.avg_hrv_change),
      distress_sessions: Number(row.distress_sessions ?? 0),
    },
    measurement: 'optional_self_reported_immediate_mood_change',
    clinical_improvement: false,
  };
}

module.exports = {
  recordSession, getHistory, getRecommendation, getSummary,
  _private: { chooseRecommendation, rankRecommendation, publicSession, assertMother },
};
