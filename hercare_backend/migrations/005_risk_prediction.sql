-- Module 4: privacy-preserving Android telemetry and versioned risk predictions.

CREATE TABLE IF NOT EXISTS device_telemetry_daily (
  id                       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id                UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_date               DATE         NOT NULL,
  timezone_offset_minutes  SMALLINT     NOT NULL CHECK (timezone_offset_minutes BETWEEN -840 AND 840),
  notifications_seen       INTEGER      NOT NULL DEFAULT 0 CHECK (notifications_seen BETWEEN 0 AND 10000),
  message_notifications    INTEGER      NOT NULL DEFAULT 0 CHECK (message_notifications BETWEEN 0 AND 10000),
  negative_notifications   INTEGER      NOT NULL DEFAULT 0 CHECK (negative_notifications BETWEEN 0 AND 10000),
  distress_notifications   INTEGER      NOT NULL DEFAULT 0 CHECK (distress_notifications BETWEEN 0 AND 10000),
  abuse_notifications      INTEGER      NOT NULL DEFAULT 0 CHECK (abuse_notifications BETWEEN 0 AND 10000),
  screen_time_minutes      INTEGER      NOT NULL DEFAULT 0 CHECK (screen_time_minutes BETWEEN 0 AND 1440),
  social_minutes           INTEGER      NOT NULL DEFAULT 0 CHECK (social_minutes BETWEEN 0 AND 1440),
  late_night_minutes       INTEGER      NOT NULL DEFAULT 0 CHECK (late_night_minutes BETWEEN 0 AND 480),
  app_switches             INTEGER      NOT NULL DEFAULT 0 CHECK (app_switches BETWEEN 0 AND 20000),
  notification_access      BOOLEAN      NOT NULL DEFAULT FALSE,
  usage_access             BOOLEAN      NOT NULL DEFAULT FALSE,
  analysis_version         VARCHAR(40)  NOT NULL,
  client_request_id        UUID         NOT NULL,
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (mother_id, local_date),
  UNIQUE (mother_id, client_request_id),
  CHECK (message_notifications <= notifications_seen),
  CHECK (negative_notifications <= message_notifications),
  CHECK (distress_notifications <= message_notifications),
  CHECK (abuse_notifications <= message_notifications)
);

CREATE TABLE IF NOT EXISTS risk_predictions (
  id                       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id                UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  model_version            VARCHAR(80)   NOT NULL,
  model_scope              VARCHAR(40)   NOT NULL CHECK (model_scope IN ('cross_sectional_baseline', 'two_week_trajectory')),
  horizon_days             SMALLINT      CHECK (horizon_days IS NULL OR horizon_days BETWEEN 1 AND 90),
  depression_probability   NUMERIC(6,5)  NOT NULL CHECK (depression_probability BETWEEN 0 AND 1),
  risk_level               VARCHAR(10)   NOT NULL CHECK (risk_level IN ('low', 'moderate', 'high', 'severe')),
  confidence               NUMERIC(6,5)  NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  data_completeness        NUMERIC(6,5)  NOT NULL CHECK (data_completeness BETWEEN 0 AND 1),
  input_summary            JSONB         NOT NULL DEFAULT '{}'::jsonb,
  contributors             JSONB         NOT NULL DEFAULT '[]'::jsonb,
  generated_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_telemetry_mother_date
  ON device_telemetry_daily(mother_id, local_date DESC);
CREATE INDEX IF NOT EXISTS idx_risk_predictions_mother_time
  ON risk_predictions(mother_id, generated_at DESC);

DROP TRIGGER IF EXISTS trg_device_telemetry_updated_at ON device_telemetry_daily;
CREATE TRIGGER trg_device_telemetry_updated_at
  BEFORE UPDATE ON device_telemetry_daily
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

