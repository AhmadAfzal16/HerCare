CREATE TABLE m4_context_checkins (
  mother_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  checkin_date DATE NOT NULL,
  financial_strain SMALLINT CHECK (financial_strain BETWEEN 0 AND 3),
  relationship_strain SMALLINT CHECK (relationship_strain BETWEEN 0 AND 3),
  support_gap SMALLINT CHECK (support_gap BETWEEN 0 AND 3),
  recovery_difficulty SMALLINT CHECK (recovery_difficulty BETWEEN 0 AND 3),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (mother_id, checkin_date)
);

CREATE TABLE m4_text_consents (
  mother_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL,
  granted_at TIMESTAMPTZ,
  CHECK (enabled = (granted_at IS NOT NULL))
);

-- Retain a versioned signal from the mother's words, without copying those words.
-- Source deletion also removes the corresponding signal.
CREATE TABLE m4_text_signals (
  mother_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  journal_id UUID UNIQUE REFERENCES journal_entries(id) ON DELETE CASCADE,
  chatbot_request_id UUID UNIQUE REFERENCES chatbot_requests(id) ON DELETE CASCADE,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  distress BOOLEAN NOT NULL,
  rule_version VARCHAR(40) NOT NULL,
  CHECK (num_nonnulls(journal_id, chatbot_request_id) = 1)
);
CREATE INDEX m4_text_signals_mother_time ON m4_text_signals(mother_id, recorded_at);
