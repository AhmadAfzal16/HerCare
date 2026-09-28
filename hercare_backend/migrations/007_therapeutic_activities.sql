-- HerCare Migration 007
-- M9: privacy-minimized therapeutic session history and recommendation feedback.

CREATE TABLE IF NOT EXISTS therapeutic_sessions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_type      VARCHAR(20) NOT NULL
                       CHECK (activity_type IN ('breathing', 'meditation', 'cbt', 'game')),
  activity_id        VARCHAR(40) NOT NULL,
  duration_seconds   INTEGER NOT NULL CHECK (duration_seconds BETWEEN 1 AND 7200),
  mood_before        SMALLINT CHECK (mood_before BETWEEN 1 AND 5),
  mood_after         SMALLINT CHECK (mood_after BETWEEN 1 AND 5),
  completed          BOOLEAN NOT NULL DEFAULT TRUE,
  client_request_id  UUID NOT NULL,
  completed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (mother_id, client_request_id)
);

CREATE INDEX IF NOT EXISTS idx_therapeutic_sessions_mother_time
  ON therapeutic_sessions(mother_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_therapeutic_sessions_activity
  ON therapeutic_sessions(mother_id, activity_type, activity_id);

