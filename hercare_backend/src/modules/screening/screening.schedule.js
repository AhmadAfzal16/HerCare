const { query } = require('../../config/database');

// App follow-up cadence, not a diagnosis or a change to questionnaire recall.
const INTERVAL_DAYS = Object.freeze({ epds: 7, phq9: 14 });

async function ensureSchedule(motherId, db = { query }) {
  await db.query(
    `INSERT INTO screening_reminders (mother_id, instrument_type, due_at)
     SELECT u.id, cadence.instrument_type,
       COALESCE(last_test.completed_at + cadence.days * INTERVAL '1 day', NOW())
     FROM users u
     CROSS JOIN (VALUES ('epds', 7), ('phq9', 14)) cadence(instrument_type, days)
     LEFT JOIN LATERAL (
       SELECT completed_at FROM screening_assessments
       WHERE mother_id = u.id AND instrument_type = cadence.instrument_type
         AND status = 'completed' ORDER BY completed_at DESC LIMIT 1
     ) last_test ON TRUE
     WHERE u.id = $1 AND u.role = 'mother' AND u.onboarding_complete = TRUE
     ON CONFLICT (mother_id, instrument_type) WHERE status = 'scheduled' DO NOTHING`,
    [motherId],
  );
}

async function getSchedule(motherId) {
  await ensureSchedule(motherId);
  const { rows } = await query(
    `SELECT sr.instrument_type, sr.due_at, sr.due_at <= NOW() AS due,
       last_test.completed_at AS last_completed_at, draft.id AS draft_id
     FROM screening_reminders sr
     LEFT JOIN LATERAL (
       SELECT completed_at FROM screening_assessments
       WHERE mother_id = sr.mother_id AND instrument_type = sr.instrument_type
         AND status = 'completed' ORDER BY completed_at DESC LIMIT 1
     ) last_test ON TRUE
     LEFT JOIN LATERAL (
       SELECT id FROM screening_assessments
       WHERE mother_id = sr.mother_id AND instrument_type = sr.instrument_type
         AND status = 'draft' ORDER BY started_at DESC LIMIT 1
     ) draft ON TRUE
     WHERE sr.mother_id = $1 AND sr.status = 'scheduled'
     ORDER BY sr.due_at, sr.instrument_type`, [motherId],
  );
  return rows.map((row) => ({ ...row, interval_days: INTERVAL_DAYS[row.instrument_type] }));
}

async function queueDueReminders(limit = 100) {
  // One durable delivery per due reminder, shared safely by multiple workers.
  const result = await query(
    `INSERT INTO notification_outbox (screening_reminder_id, recipient_id)
     SELECT sr.id, sr.mother_id FROM screening_reminders sr
     JOIN users u ON u.id = sr.mother_id AND u.role = 'mother'
       AND u.is_active = TRUE AND u.onboarding_complete = TRUE
     JOIN onboarding_data od ON od.user_id = u.id AND od.consent_tier1 = TRUE
     WHERE sr.status = 'scheduled' AND sr.due_at <= NOW()
       AND NOT EXISTS (SELECT 1 FROM notification_outbox no WHERE no.screening_reminder_id = sr.id)
     ORDER BY sr.due_at LIMIT $1
     ON CONFLICT (screening_reminder_id) DO NOTHING`, [limit],
  );
  return result.rowCount;
}

module.exports = { INTERVAL_DAYS, ensureSchedule, getSchedule, queueDueReminders };
