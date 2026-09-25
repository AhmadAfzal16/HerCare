-- Firebase Cloud Messaging device registry and durable guardian-alert outbox.
-- Tokens are encrypted by the application; only a keyed hash is indexed.

CREATE TABLE IF NOT EXISTS push_devices (
  id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash          CHAR(64)     NOT NULL UNIQUE,
  token_encrypted     TEXT         NOT NULL,
  platform            VARCHAR(10)  NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  enabled             BOOLEAN      NOT NULL DEFAULT TRUE,
  failure_count       SMALLINT     NOT NULL DEFAULT 0 CHECK (failure_count >= 0),
  last_error_code     VARCHAR(100),
  last_seen_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_push_devices_user_active
  ON push_devices(user_id) WHERE enabled = TRUE;

CREATE TABLE IF NOT EXISTS notification_outbox (
  id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id            UUID         NOT NULL UNIQUE REFERENCES guardian_alerts(id) ON DELETE CASCADE,
  recipient_id        UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status              VARCHAR(12)  NOT NULL DEFAULT 'pending'
                                   CHECK (status IN ('pending', 'sending', 'sent', 'retry', 'no_device', 'cancelled', 'failed')),
  attempts            SMALLINT     NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_attempt_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  sent_at             TIMESTAMPTZ,
  last_error          VARCHAR(300),
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_outbox_ready
  ON notification_outbox(next_attempt_at, created_at)
  WHERE status IN ('pending', 'retry', 'no_device');

CREATE OR REPLACE FUNCTION queue_guardian_push_notification()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO notification_outbox (alert_id, recipient_id)
  VALUES (NEW.id, NEW.guardian_id)
  ON CONFLICT (alert_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_queue_guardian_push_notification ON guardian_alerts;
CREATE TRIGGER trg_queue_guardian_push_notification
  AFTER INSERT ON guardian_alerts
  FOR EACH ROW EXECUTE FUNCTION queue_guardian_push_notification();

-- Queue alerts created before this migration if they are still recent/unread.
INSERT INTO notification_outbox (alert_id, recipient_id)
SELECT ga.id, ga.guardian_id
FROM guardian_alerts ga
WHERE ga.is_read = FALSE
  AND ga.triggered_at >= NOW() - INTERVAL '24 hours'
ON CONFLICT (alert_id) DO NOTHING;

DROP TRIGGER IF EXISTS trg_push_devices_updated_at ON push_devices;
CREATE TRIGGER trg_push_devices_updated_at
  BEFORE UPDATE ON push_devices
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_notification_outbox_updated_at ON notification_outbox;
CREATE TRIGGER trg_notification_outbox_updated_at
  BEFORE UPDATE ON notification_outbox
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
