const { query } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');

function publicSession(row) {
  return {
    id: row.id,
    activity_type: row.activity_type,
    activity_id: row.activity_id,
    duration_seconds: row.duration_seconds,
    mood_before: row.mood_before,
    mood_after: row.mood_after,
    mood_change: row.mood_before && row.mood_after
      ? row.mood_after - row.mood_before : null,
    completed: row.completed,
    completed_at: row.completed_at,
  };
}

async function assertMother(userId, role) {
  if (role !== 'mother') throw new AppError('Therapeutic activities are available to mother accounts.', 403);
  const result = await query('SELECT is_active FROM users WHERE id = $1 AND role = $2', [userId, 'mother']);
  if (!result.rows[0]?.is_active) throw new AppError('Account is unavailable.', 403);
}

async function recordSession(userId, role, data) {
  await assertMother(userId, role);
  const { rows } = await query(
    `INSERT INTO therapeutic_sessions
       (mother_id, activity_type, activity_id, duration_seconds, mood_before,
        mood_after, completed, client_request_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     ON CONFLICT (mother_id, client_request_id) DO UPDATE
       SET client_request_id = EXCLUDED.client_request_id
     RETURNING *`,
    [userId, data.activity_type, data.activity_id, data.duration_seconds,
      data.mood_before ?? null, data.mood_after ?? null,
      data.completed ?? true, data.client_request_id],
  );
  return publicSession(rows[0]);
}

async function getHistory(userId, role, limit = 30) {
  await assertMother(userId, role);
  const { rows } = await query(
    `SELECT * FROM therapeutic_sessions WHERE mother_id = $1
     ORDER BY completed_at DESC LIMIT $2`,
    [userId, limit],
  );
  return rows.map(publicSession);
}

function chooseRecommendation(signals) {
  if (signals.safetyPriority) {
    return {
      activity_type: 'breathing', activity_id: 'breathing_478',
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
  if ((signals.sleepQuality !== null && signals.sleepQuality <= 2)
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
    activity_type: 'breathing', activity_id: 'box_breathing',
    reason: 'A short balanced breathing session is a gentle daily reset.',
    reason_ur: 'مختصر متوازن سانس کی مشق روزانہ کا نرم سکون ہے۔',
    safety_priority: false,
  };
}

async function getRecommendation(userId, role) {
  await assertMother(userId, role);
  const [moodResult, telemetryResult, screeningResult, recentResult] = await Promise.all([
    query(`SELECT mood_rating, sleep_quality FROM mood_checkins
           WHERE mother_id = $1 ORDER BY entry_date DESC LIMIT 1`, [userId]),
    query(`SELECT screen_time_minutes, late_night_minutes FROM device_telemetry_daily
           WHERE mother_id = $1 ORDER BY local_date DESC LIMIT 1`, [userId]),
    query(`SELECT self_harm_positive FROM screening_assessments
           WHERE mother_id = $1 ORDER BY completed_at DESC LIMIT 1`, [userId]),
    query(`SELECT activity_id FROM therapeutic_sessions WHERE mother_id = $1
           ORDER BY completed_at DESC LIMIT 1`, [userId]),
  ]);
  const mood = moodResult.rows[0];
  const telemetry = telemetryResult.rows[0];
  const signals = {
    mood: mood?.mood_rating ?? null,
    sleepQuality: mood?.sleep_quality ?? null,
    screenMinutes: telemetry?.screen_time_minutes ?? 0,
    lateNightMinutes: telemetry?.late_night_minutes ?? 0,
    safetyPriority: screeningResult.rows[0]?.self_harm_positive === true,
  };
  let recommendation = chooseRecommendation(signals);
  if (!recommendation.safety_priority
      && recentResult.rows[0]?.activity_id === recommendation.activity_id) {
    recommendation = {
      activity_type: 'cbt', activity_id: 'behavior_plan',
      reason: 'Try one small achievable action for variety today.',
      reason_ur: 'آج تبدیلی کے لیے ایک چھوٹا قابلِ عمل قدم آزمائیں۔',
      safety_priority: false,
    };
  }
  return { ...recommendation, generated_at: new Date().toISOString() };
}

async function getSummary(userId, role) {
  await assertMother(userId, role);
  const { rows } = await query(
    `SELECT COUNT(*)::int AS total_sessions,
            COUNT(*) FILTER (WHERE completed = TRUE)::int AS completed_sessions,
            COALESCE(SUM(duration_seconds) FILTER (WHERE completed = TRUE), 0)::int AS total_seconds,
            ROUND(AVG(mood_after - mood_before) FILTER
              (WHERE completed = TRUE AND mood_before IS NOT NULL AND mood_after IS NOT NULL), 2) AS avg_mood_change
     FROM therapeutic_sessions WHERE mother_id = $1`,
    [userId],
  );
  const row = rows[0];
  return { ...row, avg_mood_change: row.avg_mood_change === null ? null : Number(row.avg_mood_change) };
}

module.exports = {
  recordSession, getHistory, getRecommendation, getSummary,
  _private: { chooseRecommendation, publicSession },
};

