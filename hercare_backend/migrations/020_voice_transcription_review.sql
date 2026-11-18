-- M5: explicitly requested voice transcription; no existing note is opted in.
-- Audio remains in its original encrypted storage. Draft text is encrypted too.
CREATE TABLE journal_voice_transcriptions (
  journal_id UUID PRIMARY KEY REFERENCES journal_entries(id) ON DELETE CASCADE,
  status VARCHAR(15) NOT NULL DEFAULT 'queued'
    CHECK(status IN ('queued','processing','review','confirmed','failed','no_speech')),
  revision INTEGER NOT NULL DEFAULT 1 CHECK(revision > 0),
  draft_encrypted TEXT,
  draft_safety_hint BOOLEAN NOT NULL DEFAULT FALSE,
  model_version VARCHAR(100),
  attempts SMALLINT NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 3),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  lease_token UUID,
  lease_until TIMESTAMPTZ,
  failure_code VARCHAR(30),
  confirmed_request_id UUID,
  confirmed_fingerprint CHAR(64),
  confirmed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK(status <> 'review' OR draft_encrypted IS NOT NULL),
  CHECK(status <> 'confirmed' OR (confirmed_request_id IS NOT NULL AND confirmed_at IS NOT NULL)),
  CHECK(status <> 'processing' OR (lease_token IS NOT NULL AND lease_until IS NOT NULL))
);
CREATE INDEX idx_voice_transcription_pending ON journal_voice_transcriptions(next_attempt_at,journal_id)
  WHERE status IN ('queued','processing');
