-- Module 3: versioned EPDS/PHQ-9 screening, responses, and reminders.

CREATE TABLE IF NOT EXISTS screening_assessments (
  id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id              UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  instrument_type        VARCHAR(10)  NOT NULL CHECK (instrument_type IN ('epds', 'phq9')),
  instrument_version     VARCHAR(20)  NOT NULL,
  scoring_version        VARCHAR(20)  NOT NULL,
  language               VARCHAR(5)   NOT NULL CHECK (language IN ('en', 'ur')),
  status                 VARCHAR(12)  NOT NULL DEFAULT 'draft'
                                      CHECK (status IN ('draft', 'completed', 'abandoned')),
  total_score            SMALLINT,
  risk_level             VARCHAR(10)  CHECK (risk_level IN ('low', 'moderate', 'high', 'severe')),
  self_harm_positive     BOOLEAN      NOT NULL DEFAULT FALSE,
  client_request_id      UUID         NOT NULL,
  started_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  completed_at           TIMESTAMPTZ,
  updated_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (mother_id, client_request_id),
  CHECK (
    (status = 'completed' AND total_score IS NOT NULL AND risk_level IS NOT NULL AND completed_at IS NOT NULL)
    OR status <> 'completed'
  ),
  CHECK (
    total_score IS NULL
    OR (instrument_type = 'epds' AND total_score BETWEEN 0 AND 30)
    OR (instrument_type = 'phq9' AND total_score BETWEEN 0 AND 27)
  )
);

CREATE TABLE IF NOT EXISTS screening_responses (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  assessment_id   UUID        NOT NULL REFERENCES screening_assessments(id) ON DELETE CASCADE,
  question_number SMALLINT    NOT NULL,
  option_index    SMALLINT    NOT NULL CHECK (option_index BETWEEN 0 AND 3),
  score           SMALLINT    NOT NULL CHECK (score BETWEEN 0 AND 3),
  answered_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (assessment_id, question_number)
);

CREATE TABLE IF NOT EXISTS screening_reminders (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  instrument_type   VARCHAR(10) NOT NULL CHECK (instrument_type IN ('epds', 'phq9')),
  due_at            TIMESTAMPTZ NOT NULL,
  status            VARCHAR(12) NOT NULL DEFAULT 'scheduled'
                                CHECK (status IN ('scheduled', 'sent', 'completed', 'cancelled')),
  assessment_id     UUID        REFERENCES screening_assessments(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_screening_assessments_mother_completed
  ON screening_assessments(mother_id, instrument_type, completed_at DESC)
  WHERE status = 'completed';
CREATE INDEX IF NOT EXISTS idx_screening_assessments_drafts
  ON screening_assessments(mother_id, updated_at DESC)
  WHERE status = 'draft';
CREATE INDEX IF NOT EXISTS idx_screening_reminders_due
  ON screening_reminders(due_at)
  WHERE status = 'scheduled';
CREATE UNIQUE INDEX IF NOT EXISTS uq_screening_scheduled_reminder
  ON screening_reminders(mother_id, instrument_type)
  WHERE status = 'scheduled';

ALTER TABLE crisis_events DROP CONSTRAINT IF EXISTS crisis_events_source_type_check;
ALTER TABLE crisis_events ADD CONSTRAINT crisis_events_source_type_check
  CHECK (source_type IN ('journal', 'voice_journal', 'mood', 'epds', 'phq9', 'ml_prediction', 'notification_signal'));

DROP TRIGGER IF EXISTS trg_screening_assessments_updated_at ON screening_assessments;
CREATE TRIGGER trg_screening_assessments_updated_at
  BEFORE UPDATE ON screening_assessments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_screening_reminders_updated_at ON screening_reminders;
CREATE TRIGGER trg_screening_reminders_updated_at
  BEFORE UPDATE ON screening_reminders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
