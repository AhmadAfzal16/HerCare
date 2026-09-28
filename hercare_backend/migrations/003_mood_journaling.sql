-- Module 5: private mood check-ins, encrypted journals, and crisis events.

CREATE TABLE IF NOT EXISTS mood_checkins (
  id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entry_date        DATE         NOT NULL,
  mood_rating       SMALLINT     NOT NULL CHECK (mood_rating BETWEEN 1 AND 5),
  energy_level      SMALLINT     NOT NULL CHECK (energy_level BETWEEN 1 AND 5),
  sleep_quality     SMALLINT     NOT NULL CHECK (sleep_quality BETWEEN 1 AND 5),
  social_support    SMALLINT     NOT NULL CHECK (social_support BETWEEN 1 AND 5),
  composite_score   NUMERIC(3,2) NOT NULL CHECK (composite_score BETWEEN 1 AND 5),
  client_request_id UUID         NOT NULL,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (mother_id, entry_date),
  UNIQUE (mother_id, client_request_id)
);

CREATE INDEX IF NOT EXISTS idx_mood_checkins_mother_date
  ON mood_checkins(mother_id, entry_date DESC);

CREATE TABLE IF NOT EXISTS journal_entries (
  id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id           UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  checkin_id          UUID         REFERENCES mood_checkins(id) ON DELETE SET NULL,
  entry_type          VARCHAR(10)  NOT NULL CHECK (entry_type IN ('text', 'voice')),
  language            VARCHAR(5)   NOT NULL CHECK (language IN ('en', 'ur', 'mixed')),
  content_encrypted   TEXT,
  search_terms        TEXT[]       NOT NULL DEFAULT '{}',
  voice_object_key    TEXT,
  voice_content_type  VARCHAR(50),
  voice_size_bytes    INTEGER      CHECK (voice_size_bytes IS NULL OR voice_size_bytes BETWEEN 1 AND 8388608),
  processing_status   VARCHAR(15)  NOT NULL DEFAULT 'complete'
                       CHECK (processing_status IN ('uploading', 'pending', 'processing', 'complete', 'failed')),
  sentiment_label     VARCHAR(10)  CHECK (sentiment_label IN ('positive', 'neutral', 'negative')),
  sentiment_score     NUMERIC(4,3) CHECK (sentiment_score IS NULL OR sentiment_score BETWEEN -1 AND 1),
  distress_score      NUMERIC(4,3) CHECK (distress_score IS NULL OR distress_score BETWEEN 0 AND 1),
  contains_danger     BOOLEAN      NOT NULL DEFAULT FALSE,
  analysis_version    VARCHAR(30),
  client_request_id   UUID         NOT NULL,
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (mother_id, client_request_id),
  CHECK (
    (entry_type = 'text' AND content_encrypted IS NOT NULL) OR
    (entry_type = 'voice' AND voice_object_key IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_journal_entries_mother_created
  ON journal_entries(mother_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_journal_entries_search_terms
  ON journal_entries USING GIN(search_terms);

CREATE TABLE IF NOT EXISTS crisis_events (
  id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id      UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_type    VARCHAR(20)  NOT NULL CHECK (source_type IN ('journal', 'voice_journal', 'mood')),
  source_id      UUID         NOT NULL,
  severity       VARCHAR(10)  NOT NULL CHECK (severity IN ('high', 'severe')),
  status         VARCHAR(15)  NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'acknowledged', 'resolved')),
  triggered_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  resolved_at    TIMESTAMPTZ,
  UNIQUE (source_type, source_id)
);

CREATE INDEX IF NOT EXISTS idx_crisis_events_mother_time
  ON crisis_events(mother_id, triggered_at DESC);

DROP TRIGGER IF EXISTS trg_mood_checkins_updated_at ON mood_checkins;
CREATE TRIGGER trg_mood_checkins_updated_at
  BEFORE UPDATE ON mood_checkins
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_journal_entries_updated_at ON journal_entries;
CREATE TRIGGER trg_journal_entries_updated_at
  BEFORE UPDATE ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
