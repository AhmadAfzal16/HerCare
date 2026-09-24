const { query, withTransaction } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const guardianService = require('../guardian/guardian.service');
const modelClient = require('./risk.client');

function asNumber(value) {
  return value === null || value === undefined ? null : Number(value);
}

function summarizeMood(rows) {
  if (!rows.length) {
    return {
      average_mood: null,
      mood_slope: null,
      average_energy: null,
      average_sleep_quality: null,
      average_social_support: null,
      mood_days: 0,
    };
  }
  const average = (field) => rows.reduce((sum, row) => sum + Number(row[field]), 0) / rows.length;
  const moods = rows.map((row) => Number(row.mood_rating));
  const meanX = (moods.length - 1) / 2;
  const meanY = moods.reduce((sum, value) => sum + value, 0) / moods.length;
  const denominator = moods.reduce((sum, _value, index) => sum + ((index - meanX) ** 2), 0);
  const slope = denominator === 0 ? 0 : moods.reduce(
    (sum, value, index) => sum + ((index - meanX) * (value - meanY)), 0,
  ) / denominator;
  return {
    average_mood: average('mood_rating'),
    mood_slope: slope,
    average_energy: average('energy_level'),
    average_sleep_quality: average('sleep_quality'),
    average_social_support: average('social_support'),
    mood_days: rows.length,
  };
}

function summarizeTelemetry(rows) {
  const totals = rows.reduce((summary, row) => ({
    messages: summary.messages + Number(row.message_notifications),
    negative: summary.negative + Number(row.negative_notifications),
    distress: summary.distress + Number(row.distress_notifications),
    abuse: summary.abuse + Number(row.abuse_notifications),
    screen: summary.screen + Number(row.screen_time_minutes),
    social: summary.social + Number(row.social_minutes),
    lateNight: summary.lateNight + Number(row.late_night_minutes),
  }), {
    messages: 0, negative: 0, distress: 0, abuse: 0, screen: 0, social: 0, lateNight: 0,
  });
  const days = rows.length;
  const ratio = (value) => (totals.messages ? value / totals.messages : 0);
  return {
    negative_notification_ratio: ratio(totals.negative),
    distress_notification_ratio: ratio(totals.distress),
    abuse_notification_ratio: ratio(totals.abuse),
    average_screen_minutes: days ? totals.screen / days : null,
    average_social_minutes: days ? totals.social / days : null,
    average_late_night_minutes: days ? totals.lateNight / days : null,
    telemetry_days: days,
  };
}

function financialStrain(incomeRange) {
  if (!incomeRange) return null;
  const numbers = String(incomeRange).match(/\d+/g);
  if (!numbers?.length) return null;
  return Number(numbers[0]) < 50000 ? 1 : 0;
}

function supportQuality(primarySupport) {
  if (primarySupport === 'none') return 0;
  if (primarySupport === 'mother_in_law') return 0.5;
  if (primarySupport) return 1;
  return null;
}

function telemetryDateAgeDays(localDate, timezoneOffsetMinutes, now = new Date()) {
  const requested = new Date(`${localDate}T00:00:00.000Z`);
  if (Number.isNaN(requested.getTime())) return Number.NaN;
  const localNow = new Date(now.getTime() - (timezoneOffsetMinutes * 60000));
  const localMidnightUtc = Date.UTC(
    localNow.getUTCFullYear(), localNow.getUTCMonth(), localNow.getUTCDate(),
  );
  return Math.floor((localMidnightUtc - requested.getTime()) / 86400000);
}

async function assertTelemetryConsent(db, motherId) {
  const { rows } = await db.query(
    'SELECT consent_tier3 FROM onboarding_data WHERE user_id = $1',
    [motherId],
  );
  if (!rows[0]?.consent_tier3) {
    throw new AppError('Notification and usage monitoring consent is required.', 403);
  }
}

async function saveTelemetry(motherId, data) {
  const ageDays = telemetryDateAgeDays(data.local_date, data.timezone_offset_minutes);
  if (Number.isNaN(ageDays) || ageDays < 0 || ageDays > 14) {
    throw new AppError('Telemetry date must be within the last 14 days.', 422);
  }
  if (data.message_notifications > data.notifications_seen
      || data.negative_notifications > data.message_notifications
      || data.distress_notifications > data.message_notifications
      || data.abuse_notifications > data.message_notifications) {
    throw new AppError('Telemetry counters are inconsistent.', 422);
  }
  return withTransaction(async (client) => {
    await assertTelemetryConsent(client, motherId);
    const duplicate = await client.query(
      'SELECT * FROM device_telemetry_daily WHERE mother_id = $1 AND client_request_id = $2',
      [motherId, data.client_request_id],
    );
    if (duplicate.rows[0]) return duplicate.rows[0];
    const fields = [
      'timezone_offset_minutes', 'notifications_seen', 'message_notifications',
      'negative_notifications', 'distress_notifications', 'abuse_notifications',
      'screen_time_minutes', 'social_minutes', 'late_night_minutes', 'app_switches',
      'notification_access', 'usage_access', 'analysis_version', 'client_request_id',
    ];
    const values = fields.map((field) => data[field]);
    const assignments = fields.map((field, index) => `${field} = $${index + 3}`).join(', ');
    const { rows } = await client.query(
      `INSERT INTO device_telemetry_daily
         (mother_id, local_date, ${fields.join(', ')})
       VALUES ($1, $2, ${fields.map((_field, index) => `$${index + 3}`).join(', ')})
       ON CONFLICT (mother_id, local_date) DO UPDATE SET ${assignments}, updated_at = NOW()
       RETURNING *`,
      [motherId, data.local_date, ...values],
    );
    return rows[0];
  });
}

async function buildFeatures(motherId) {
  const [profileResult, screeningResult, moodResult, telemetryResult] = await Promise.all([
    query('SELECT * FROM onboarding_data WHERE user_id = $1', [motherId]),
    query(
      `SELECT DISTINCT ON (instrument_type)
         instrument_type, total_score, self_harm_positive, completed_at
       FROM screening_assessments
       WHERE mother_id = $1 AND status = 'completed'
       ORDER BY instrument_type, completed_at DESC`,
      [motherId],
    ),
    query(
      `SELECT mood_rating, energy_level, sleep_quality, social_support, entry_date
       FROM mood_checkins WHERE mother_id = $1 AND entry_date >= CURRENT_DATE - 13
       ORDER BY entry_date`,
      [motherId],
    ),
    query(
      `SELECT * FROM device_telemetry_daily
       WHERE mother_id = $1 AND local_date >= CURRENT_DATE - 13 ORDER BY local_date`,
      [motherId],
    ),
  ]);
  const profile = profileResult.rows[0];
  if (!profile) throw new AppError('Complete onboarding before generating risk insights.', 409);
  const screenings = Object.fromEntries(
    screeningResult.rows.map((row) => [row.instrument_type, row]),
  );
  const mood = summarizeMood(moodResult.rows);
  const telemetry = summarizeTelemetry(telemetryResult.rows);
  const safetyPositive = Object.values(screenings).some((row) => row.self_harm_positive);
  return {
    age: asNumber(profile.age),
    parity: asNumber(profile.parity),
    education_level: profile.education_level,
    household_type: profile.household_type,
    financial_strain: financialStrain(profile.income_range),
    support_quality: supportQuality(profile.primary_support),
    cesarean: profile.delivery_method === 'cesarean' ? 1 : 0,
    baby_female: profile.baby_gender === 'female' ? 1 : 0,
    obstetric_complications: [
      profile.has_preeclampsia,
      profile.has_postpartum_hemorrhage,
      profile.has_preterm_birth,
      profile.has_gestational_diabetes,
    ].filter(Boolean).length,
    latest_epds_score: asNumber(screenings.epds?.total_score),
    latest_phq9_score: asNumber(screenings.phq9?.total_score),
    safety_positive: safetyPositive,
    ...mood,
    ...telemetry,
  };
}

function publicPrediction(row) {
  if (!row) return null;
  return {
    id: row.id,
    model_version: row.model_version,
    model_scope: row.model_scope,
    horizon_days: row.horizon_days === null ? null : Number(row.horizon_days),
    depression_probability: Number(row.depression_probability),
    risk_level: row.risk_level,
    confidence: Number(row.confidence),
    data_completeness: Number(row.data_completeness),
    contributors: row.contributors,
    generated_at: row.generated_at,
    is_clinical_forecast: row.model_scope === 'two_week_trajectory',
  };
}

async function updateReports(motherId, prediction) {
  const dates = guardianService._private.getCanonicalPeriod;
  let weeklyReportId = null;
  for (const periodType of ['daily', 'weekly', 'monthly']) {
    const { periodStart, periodEnd } = dates(periodType, new Date());
    const reportData = JSON.stringify({
      latest_prediction: {
        prediction_id: prediction.id,
        risk_level: prediction.risk_level,
        confidence: prediction.confidence,
        model_version: prediction.model_version,
        generated_at: prediction.generated_at,
      },
    });
    const { rows } = await query(
      `INSERT INTO health_reports
         (mother_id, period_type, period_start, period_end, risk_level, report_data)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb)
       ON CONFLICT (mother_id, period_type, period_start, period_end)
       DO UPDATE SET risk_level = EXCLUDED.risk_level,
         report_data = health_reports.report_data || EXCLUDED.report_data,
         updated_at = NOW()
       RETURNING id`,
      [motherId, periodType, periodStart, periodEnd, prediction.risk_level, reportData],
    );
    if (periodType === 'weekly') weeklyReportId = rows[0].id;
  }
  return weeklyReportId;
}

async function generatePrediction(motherId) {
  const features = await buildFeatures(motherId);
  const result = await modelClient.predict(features);
  const { rows } = await query(
    `INSERT INTO risk_predictions
       (mother_id, model_version, model_scope, horizon_days, depression_probability,
        risk_level, confidence, data_completeness, input_summary, contributors)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb) RETURNING *`,
    [
      motherId,
      result.model_version,
      result.model_scope,
      result.horizon_days,
      result.depression_probability,
      result.risk_level,
      result.confidence,
      result.data_completeness,
      JSON.stringify({
        mood_days: features.mood_days,
        telemetry_days: features.telemetry_days,
        has_epds: features.latest_epds_score !== null,
        has_phq9: features.latest_phq9_score !== null,
      }),
      JSON.stringify(result.contributors || []),
    ],
  );
  const prediction = publicPrediction(rows[0]);
  if (prediction.is_clinical_forecast
      && ['high', 'severe'].includes(prediction.risk_level)) {
    const reportId = await updateReports(motherId, prediction);
    await query(
      `INSERT INTO crisis_events (mother_id, source_type, source_id, severity)
       VALUES ($1, 'ml_prediction', $2, $3)
       ON CONFLICT (source_type, source_id) DO NOTHING`,
      [motherId, prediction.id, prediction.risk_level],
    );
    await guardianService.notifyGuardian(motherId, prediction.risk_level, reportId);
  }
  return prediction;
}

async function getLatest(motherId) {
  const { rows } = await query(
    'SELECT * FROM risk_predictions WHERE mother_id = $1 ORDER BY generated_at DESC LIMIT 1',
    [motherId],
  );
  return publicPrediction(rows[0]);
}

async function getHistory(motherId, limit = 20) {
  const { rows } = await query(
    `SELECT * FROM risk_predictions WHERE mother_id = $1
     ORDER BY generated_at DESC LIMIT $2`,
    [motherId, limit],
  );
  return rows.map(publicPrediction);
}

async function getStatus(motherId) {
  const { rows } = await query(
    `SELECT consent_tier3 FROM onboarding_data WHERE user_id = $1`,
    [motherId],
  );
  const latestTelemetry = await query(
    `SELECT local_date, notification_access, usage_access, updated_at
     FROM device_telemetry_daily WHERE mother_id = $1 ORDER BY local_date DESC LIMIT 1`,
    [motherId],
  );
  return {
    consent_tier3: rows[0]?.consent_tier3 === true,
    latest_telemetry: latestTelemetry.rows[0] || null,
  };
}

async function updateConsent(motherId, enabled) {
  const { rows } = await query(
    `UPDATE onboarding_data SET consent_tier3 = $1, updated_at = NOW()
     WHERE user_id = $2 RETURNING consent_tier3`,
    [enabled, motherId],
  );
  if (!rows[0]) throw new AppError('Complete onboarding before changing monitoring consent.', 409);
  return { consent_tier3: rows[0].consent_tier3 };
}

module.exports = {
  saveTelemetry,
  generatePrediction,
  getLatest,
  getHistory,
  getStatus,
  updateConsent,
  _private: {
    summarizeMood,
    summarizeTelemetry,
    financialStrain,
    supportQuality,
    telemetryDateAgeDays,
  },
};
