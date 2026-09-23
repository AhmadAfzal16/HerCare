-- HerCare Migration 002
-- Guardian health reports & alert history
-- Run: psql -U hercare_user -d hercare_db -f migrations/002_guardian_reports.sql

-- Harden the link created by migration 001. Invite codes expire server-side and
-- a mother/guardian can have only one active relationship at a time.
ALTER TABLE guardian_links
  ADD COLUMN IF NOT EXISTS guardian_name VARCHAR(60),
  ADD COLUMN IF NOT EXISTS relationship VARCHAR(20),
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE guardian_links
SET expires_at = created_at + INTERVAL '24 hours'
WHERE expires_at IS NULL AND status = 'pending';

UPDATE guardian_links
SET status = 'revoked', revoked_at = NOW()
WHERE status = 'pending' AND LENGTH(invite_code) <> 12;

ALTER TABLE guardian_links
  DROP CONSTRAINT IF EXISTS guardian_links_relationship_check;
ALTER TABLE guardian_links
  ADD CONSTRAINT guardian_links_relationship_check
  CHECK (relationship IS NULL OR relationship IN
    ('husband','mother','sister','brother','father','friend','other'));

WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY mother_id ORDER BY accepted_at DESC NULLS LAST, created_at DESC
  ) AS position
  FROM guardian_links WHERE status = 'active'
)
UPDATE guardian_links gl
SET status = 'revoked', revoked_at = NOW()
FROM ranked WHERE gl.id = ranked.id AND ranked.position > 1;

WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY guardian_id ORDER BY accepted_at DESC NULLS LAST, created_at DESC
  ) AS position
  FROM guardian_links WHERE status = 'active' AND guardian_id IS NOT NULL
)
UPDATE guardian_links gl
SET status = 'revoked', revoked_at = NOW()
FROM ranked WHERE gl.id = ranked.id AND ranked.position > 1;

WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY mother_id ORDER BY created_at DESC
  ) AS position
  FROM guardian_links WHERE status = 'pending'
)
UPDATE guardian_links gl
SET status = 'revoked', revoked_at = NOW()
FROM ranked WHERE gl.id = ranked.id AND ranked.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_guardian_links_active_mother
  ON guardian_links(mother_id) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS uq_guardian_links_active_guardian
  ON guardian_links(guardian_id) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS uq_guardian_links_pending_mother
  ON guardian_links(mother_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_guardian_links_pending_expiry
  ON guardian_links(expires_at) WHERE status = 'pending';

-- ─── Health Reports ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS health_reports (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  period_type   VARCHAR(10)  NOT NULL CHECK (period_type IN ('daily','weekly','monthly')),
  period_start  DATE         NOT NULL,
  period_end    DATE         NOT NULL,
  avg_mood      NUMERIC(3,1),                -- 1.0–5.0 composite score
  epds_score    SMALLINT,                    -- latest EPDS score in period
  risk_level    VARCHAR(10)  CHECK (risk_level IN ('low','moderate','high','severe')),
  sleep_avg_h   NUMERIC(3,1),               -- avg hours slept per night
  mood_entries  SMALLINT     DEFAULT 0,      -- number of mood logs in period
  report_data   JSONB        NOT NULL DEFAULT '{}', -- full aggregated payload
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT health_reports_period_valid CHECK (period_end >= period_start),
  CONSTRAINT health_reports_avg_mood_valid CHECK (avg_mood IS NULL OR avg_mood BETWEEN 1 AND 5),
  CONSTRAINT health_reports_epds_valid CHECK (epds_score IS NULL OR epds_score BETWEEN 0 AND 30),
  CONSTRAINT health_reports_sleep_valid CHECK (sleep_avg_h IS NULL OR sleep_avg_h BETWEEN 0 AND 24),
  CONSTRAINT health_reports_mood_entries_valid CHECK (mood_entries >= 0),
  CONSTRAINT health_reports_period_unique UNIQUE (mother_id, period_type, period_start, period_end)
);

ALTER TABLE health_reports
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY mother_id, period_type, period_start, period_end
    ORDER BY created_at DESC
  ) AS position
  FROM health_reports
)
DELETE FROM health_reports hr
USING ranked WHERE hr.id = ranked.id AND ranked.position > 1;

ALTER TABLE health_reports DROP CONSTRAINT IF EXISTS health_reports_period_valid;
ALTER TABLE health_reports ADD CONSTRAINT health_reports_period_valid
  CHECK (period_end >= period_start);
ALTER TABLE health_reports DROP CONSTRAINT IF EXISTS health_reports_avg_mood_valid;
ALTER TABLE health_reports ADD CONSTRAINT health_reports_avg_mood_valid
  CHECK (avg_mood IS NULL OR avg_mood BETWEEN 1 AND 5);
ALTER TABLE health_reports DROP CONSTRAINT IF EXISTS health_reports_epds_valid;
ALTER TABLE health_reports ADD CONSTRAINT health_reports_epds_valid
  CHECK (epds_score IS NULL OR epds_score BETWEEN 0 AND 30);
ALTER TABLE health_reports DROP CONSTRAINT IF EXISTS health_reports_sleep_valid;
ALTER TABLE health_reports ADD CONSTRAINT health_reports_sleep_valid
  CHECK (sleep_avg_h IS NULL OR sleep_avg_h BETWEEN 0 AND 24);
ALTER TABLE health_reports DROP CONSTRAINT IF EXISTS health_reports_mood_entries_valid;
ALTER TABLE health_reports ADD CONSTRAINT health_reports_mood_entries_valid
  CHECK (mood_entries >= 0);
ALTER TABLE health_reports DROP CONSTRAINT IF EXISTS health_reports_period_unique;
ALTER TABLE health_reports ADD CONSTRAINT health_reports_period_unique
  UNIQUE (mother_id, period_type, period_start, period_end);

CREATE INDEX IF NOT EXISTS idx_health_reports_mother      ON health_reports(mother_id);
CREATE INDEX IF NOT EXISTS idx_health_reports_period_type ON health_reports(mother_id, period_type, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_health_reports_start       ON health_reports(period_start DESC);

-- ─── Guardian Alerts ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS guardian_alerts (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  guardian_id   UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  report_id     UUID         REFERENCES health_reports(id) ON DELETE CASCADE,
  alert_type    VARCHAR(30)  NOT NULL
                  CHECK (alert_type IN ('risk_high','risk_severe','mood_drop','epds_spike','crisis')),
  message       TEXT         NOT NULL,
  is_read       BOOLEAN      NOT NULL DEFAULT FALSE,
  triggered_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

ALTER TABLE guardian_alerts
  ADD COLUMN IF NOT EXISTS report_id UUID REFERENCES health_reports(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_guardian_alerts_guardian ON guardian_alerts(guardian_id, is_read);
CREATE INDEX IF NOT EXISTS idx_guardian_alerts_mother   ON guardian_alerts(mother_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_guardian_alerts_report_type
  ON guardian_alerts(guardian_id, report_id, alert_type)
  WHERE report_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_guardian_links_updated_at ON guardian_links;
CREATE TRIGGER trg_guardian_links_updated_at
  BEFORE UPDATE ON guardian_links
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_health_reports_updated_at ON health_reports;
CREATE TRIGGER trg_health_reports_updated_at
  BEFORE UPDATE ON health_reports
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
