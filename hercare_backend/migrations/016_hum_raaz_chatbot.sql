-- M6 Hum-Raaz is private mother/assistant conversation, NOT guardian messaging.
-- Application-layer authenticated AES-GCM encrypts all text and context snapshots.
CREATE TABLE IF NOT EXISTS chatbot_consents (
  mother_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  policy_version VARCHAR(50) NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  granted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS chatbot_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  language VARCHAR(10) NOT NULL CHECK (language IN ('en','ur','roman_ur')),
  state_encrypted TEXT,
  state_personalized BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ(3) NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_message_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_chatbot_sessions_mother_time
  ON chatbot_sessions(mother_id,created_at DESC,id DESC);
CREATE TABLE IF NOT EXISTS chatbot_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES chatbot_sessions(id) ON DELETE CASCADE,
  client_request_id UUID NOT NULL,
  content_hash VARCHAR(64) NOT NULL,
  language VARCHAR(10) NOT NULL CHECK (language IN ('en','ur','roman_ur')),
  status VARCHAR(12) NOT NULL CHECK (status IN ('processing','complete','failed')),
  personalization_used BOOLEAN NOT NULL DEFAULT FALSE,
  lease_id UUID NOT NULL,
  lease_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  consent_snapshot_encrypted TEXT NOT NULL,
  context_encrypted TEXT NOT NULL,
  reply_encrypted TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  UNIQUE(session_id,client_request_id)
);
-- Only one response can alter a session's turn order/state at a time.
CREATE UNIQUE INDEX IF NOT EXISTS uq_chatbot_processing_session
  ON chatbot_requests(session_id) WHERE status='processing';
CREATE TABLE IF NOT EXISTS chatbot_turns (
  ordinal BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES chatbot_sessions(id) ON DELETE CASCADE,
  request_id UUID NOT NULL REFERENCES chatbot_requests(id) ON DELETE CASCADE,
  role VARCHAR(10) NOT NULL CHECK (role IN ('user','assistant')),
  language VARCHAR(10) NOT NULL CHECK (language IN ('en','ur','roman_ur')),
  content_encrypted TEXT NOT NULL,
  metadata_encrypted TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(request_id,role)
);
CREATE INDEX IF NOT EXISTS idx_chatbot_turns_session_time
  ON chatbot_turns(session_id,ordinal DESC);
ALTER TABLE crisis_events DROP CONSTRAINT IF EXISTS crisis_events_source_type_check;
ALTER TABLE crisis_events ADD CONSTRAINT crisis_events_source_type_check CHECK (source_type IN (
  'journal','voice_journal','mood','epds','phq9','ml_prediction','notification_signal','chat','chatbot'
));
