-- Reuse the encrypted device registry and durable FCM worker for mother reminders.
ALTER TABLE notification_outbox ALTER COLUMN alert_id DROP NOT NULL;
ALTER TABLE notification_outbox ADD COLUMN screening_reminder_id UUID UNIQUE
  REFERENCES screening_reminders(id) ON DELETE CASCADE;
ALTER TABLE notification_outbox ADD CONSTRAINT notification_exactly_one_source
  CHECK ((alert_id IS NOT NULL)::int + (screening_reminder_id IS NOT NULL)::int = 1);

-- Correct the old shared seven-day cadence, without changing completed results.
UPDATE screening_reminders sr SET due_at = latest.completed_at + INTERVAL '14 days', updated_at = NOW()
FROM (
  SELECT mother_id, MAX(completed_at) AS completed_at FROM screening_assessments
  WHERE instrument_type = 'phq9' AND status = 'completed' GROUP BY mother_id
) latest
WHERE sr.mother_id = latest.mother_id AND sr.instrument_type = 'phq9' AND sr.status = 'scheduled';

-- First tests are due immediately; existing completed tests retain their cadence.
INSERT INTO screening_reminders (mother_id, instrument_type, due_at)
SELECT u.id, cadence.instrument_type,
  COALESCE(last_test.completed_at + cadence.days * INTERVAL '1 day', NOW())
FROM users u
CROSS JOIN (VALUES ('epds', 7), ('phq9', 14)) cadence(instrument_type, days)
LEFT JOIN LATERAL (
  SELECT completed_at FROM screening_assessments
  WHERE mother_id = u.id AND instrument_type = cadence.instrument_type
    AND status = 'completed' ORDER BY completed_at DESC LIMIT 1
) last_test ON TRUE
WHERE u.role = 'mother' AND u.is_active = TRUE AND u.onboarding_complete = TRUE
ON CONFLICT (mother_id, instrument_type) WHERE status = 'scheduled' DO NOTHING;
