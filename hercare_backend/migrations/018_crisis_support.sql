-- M10 private safety plans and explicit, idempotent requests for support.
-- Existing crisis records remain intact. Closing a record is not clinical recovery.
CREATE TABLE IF NOT EXISTS crisis_safety_plans (
  mother_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  content_encrypted TEXT,
  version INTEGER NOT NULL DEFAULT 0 CHECK (version >= 0),
  safe_guardian_link_id UUID REFERENCES guardian_links(id) ON DELETE SET NULL,
  guardian_contact_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
  guardian_confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE crisis_events DROP CONSTRAINT IF EXISTS crisis_events_source_type_check;
ALTER TABLE crisis_events ADD CONSTRAINT crisis_events_source_type_check CHECK (source_type IN (
  'journal','voice_journal','mood','epds','phq9','ml_prediction','notification_signal','chat','chatbot','manual'
));
ALTER TABLE crisis_events ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;
ALTER TABLE crisis_events ADD COLUMN IF NOT EXISTS resolution_outcome VARCHAR(30)
  CHECK (resolution_outcome IN ('support_contacted','professional_help_contacted','accidental_activation','other'));
CREATE INDEX IF NOT EXISTS idx_crisis_events_open_mother
  ON crisis_events(mother_id,triggered_at DESC,id DESC) WHERE status <> 'resolved';

CREATE TABLE IF NOT EXISTS crisis_support_requests (
  mother_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_request_id UUID NOT NULL,
  event_id UUID NOT NULL UNIQUE REFERENCES crisis_events(id) ON DELETE CASCADE,
  request_fingerprint CHAR(64) NOT NULL,
  guardian_notification VARCHAR(15) NOT NULL
    CHECK (guardian_notification IN ('not_requested','queued','unavailable')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (mother_id,client_request_id)
);
ALTER TABLE guardian_alerts ADD COLUMN IF NOT EXISTS crisis_event_id UUID
  REFERENCES crisis_events(id) ON DELETE CASCADE;
ALTER TABLE guardian_alerts ADD COLUMN IF NOT EXISTS crisis_guardian_link_id UUID
  REFERENCES guardian_links(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_guardian_alerts_crisis_event
  ON guardian_alerts(crisis_event_id) WHERE crisis_event_id IS NOT NULL;

-- Tier 2 sharing alone is NOT a declaration that a spouse is a safe crisis recipient.
-- Return NULL rather than raising: unsafe alert delivery must not prevent saving
-- the mother's private journal, screening, chat or crisis record.
CREATE OR REPLACE FUNCTION enforce_safe_urgent_guardian_recipient()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.alert_type NOT IN ('crisis','risk_severe') THEN RETURN NEW; END IF;
  IF NEW.crisis_event_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM crisis_events event WHERE event.id=NEW.crisis_event_id
      AND event.mother_id=NEW.mother_id AND event.status<>'resolved'
  ) THEN RETURN NULL; END IF;
  SELECT gl.id INTO NEW.crisis_guardian_link_id FROM guardian_links gl
    JOIN users mother ON mother.id=gl.mother_id AND mother.is_active AND mother.role='mother'
    JOIN users guardian ON guardian.id=gl.guardian_id AND guardian.is_active AND guardian.role='guardian'
    JOIN onboarding_data od ON od.user_id=gl.mother_id AND od.consent_tier1 AND od.consent_tier2
    JOIN crisis_safety_plans plan ON plan.mother_id=gl.mother_id
      AND plan.safe_guardian_link_id=gl.id AND plan.guardian_contact_confirmed
    WHERE gl.mother_id=NEW.mother_id AND gl.guardian_id=NEW.guardian_id AND gl.status='active'
    LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_safe_urgent_guardian_recipient ON guardian_alerts;
CREATE TRIGGER trg_safe_urgent_guardian_recipient BEFORE INSERT ON guardian_alerts
  FOR EACH ROW EXECUTE FUNCTION enforce_safe_urgent_guardian_recipient();
