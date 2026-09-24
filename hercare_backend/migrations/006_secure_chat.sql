-- HerCare Migration 006
-- M7: private mother/guardian chat with encrypted messages and safety metadata.

CREATE TABLE IF NOT EXISTS chat_conversations (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  guardian_link_id   UUID NOT NULL UNIQUE REFERENCES guardian_links(id) ON DELETE CASCADE,
  mother_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  guardian_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_message_at    TIMESTAMPTZ,
  CHECK (mother_id <> guardian_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_conversations_mother
  ON chat_conversations(mother_id);
CREATE INDEX IF NOT EXISTS idx_chat_conversations_guardian
  ON chat_conversations(guardian_id);

CREATE TABLE IF NOT EXISTS chat_messages (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id    UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
  sender_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content_encrypted  TEXT NOT NULL,
  language           VARCHAR(10) NOT NULL CHECK (language IN ('en', 'ur', 'mixed')),
  sentiment_label    VARCHAR(10) NOT NULL CHECK (sentiment_label IN ('positive', 'neutral', 'negative')),
  sentiment_score    NUMERIC(5,3) NOT NULL CHECK (sentiment_score BETWEEN -1 AND 1),
  distress_score     NUMERIC(5,3) NOT NULL CHECK (distress_score BETWEEN 0 AND 1),
  contains_danger    BOOLEAN NOT NULL DEFAULT FALSE,
  analysis_version   VARCHAR(40) NOT NULL,
  client_request_id  UUID NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at            TIMESTAMPTZ,
  UNIQUE (sender_id, client_request_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation_time
  ON chat_messages(conversation_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_unread
  ON chat_messages(conversation_id, read_at) WHERE read_at IS NULL;

-- M5 originally limited crisis sources to journals and mood. M7 adds chat.
ALTER TABLE crisis_events DROP CONSTRAINT IF EXISTS crisis_events_source_type_check;
ALTER TABLE crisis_events ADD CONSTRAINT crisis_events_source_type_check
  CHECK (source_type IN (
    'journal', 'voice_journal', 'mood', 'epds', 'phq9',
    'ml_prediction', 'notification_signal', 'chat'
  ));
