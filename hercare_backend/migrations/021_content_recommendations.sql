-- M11: reviewed, database-managed content. No fabricated or auto-published media.
-- This migration defines storage only; operators import drafts, review, then publish.
CREATE TABLE content_catalog_state (
  singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  policy_version INTEGER NOT NULL DEFAULT 1 CHECK (policy_version > 0),
  weights JSONB NOT NULL DEFAULT '{"context":30,"helpful":18,"not_helpful":-25,"practice":12,"saved":5,"rotation":6,"category_cap":3}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO content_catalog_state(singleton) VALUES(TRUE);

CREATE TABLE content_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  status VARCHAR(12) NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','reviewed','published','archived')),
  title_en VARCHAR(180) NOT NULL,
  title_ur VARCHAR(240) NOT NULL,
  summary_en VARCHAR(800) NOT NULL,
  summary_ur VARCHAR(1000) NOT NULL,
  body_en TEXT,
  body_ur TEXT,
  category VARCHAR(20) NOT NULL CHECK(category IN ('quran','islamic','soothing','psychoeducation','bonding','game','activity')),
  format VARCHAR(12) NOT NULL CHECK(format IN ('article','audio','video','activity')),
  audience VARCHAR(10) NOT NULL CHECK(audience IN ('mother','guardian','both')),
  is_religious BOOLEAN NOT NULL DEFAULT FALSE,
  is_music BOOLEAN NOT NULL DEFAULT FALSE,
  media_url TEXT,
  source_url TEXT,
  source_name VARCHAR(180),
  license_name VARCHAR(300),
  attribution VARCHAR(1000),
  arabic_text TEXT,
  transliteration TEXT,
  verse_reference VARCHAR(80),
  activity_type VARCHAR(20),
  activity_id VARCHAR(40),
  duration_seconds INTEGER CHECK(duration_seconds BETWEEN 1 AND 7200),
  tags TEXT[] NOT NULL DEFAULT '{}',
  priority SMALLINT NOT NULL DEFAULT 0 CHECK(priority BETWEEN 0 AND 100),
  available_from TIMESTAMPTZ,
  available_until TIMESTAMPTZ,
  review_after TIMESTAMPTZ,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  review_note VARCHAR(1500),
  reviewer_qualification VARCHAR(300),
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK(available_until IS NULL OR available_from IS NULL OR available_until > available_from),
  CHECK(cardinality(tags) <= 20),
  CHECK(category NOT IN ('quran','islamic') OR is_religious),
  CHECK(format <> 'activity' OR (activity_type IS NOT NULL AND activity_id IS NOT NULL)),
  CHECK(format NOT IN ('audio','video') OR media_url IS NOT NULL),
  CHECK(status NOT IN ('reviewed','published') OR (reviewed_at IS NOT NULL AND review_note IS NOT NULL AND reviewer_qualification IS NOT NULL)),
  CHECK(status <> 'published' OR published_at IS NOT NULL)
);
CREATE INDEX idx_content_live ON content_items(priority DESC, published_at DESC, id) WHERE status='published';
CREATE INDEX idx_content_tags ON content_items USING gin(tags) WHERE status='published';
CREATE INDEX idx_content_admin ON content_items(status,updated_at DESC,id DESC);

CREATE TABLE content_preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  religious_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  music_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  disabled_categories TEXT[] NOT NULL DEFAULT '{}',
  version INTEGER NOT NULL DEFAULT 1 CHECK(version > 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK(disabled_categories <@ ARRAY['quran','islamic','soothing','psychoeducation','bonding','game','activity']::text[])
);
CREATE TABLE content_feedback (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content_id UUID NOT NULL REFERENCES content_items(id) ON DELETE CASCADE,
  value VARCHAR(12) NOT NULL CHECK(value IN ('helpful','not_helpful','dismissed')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(user_id,content_id)
);
CREATE TABLE content_saves (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content_id UUID NOT NULL REFERENCES content_items(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(user_id,content_id)
);
CREATE INDEX idx_content_saves_user_time ON content_saves(user_id,created_at DESC,content_id);
-- Retry receipts contain only IDs/booleans and bounded response metadata, never health data.
CREATE TABLE content_mutations (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_request_id UUID NOT NULL,
  fingerprint CHAR(64) NOT NULL,
  response JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(user_id,client_request_id)
);
CREATE INDEX idx_content_mutations_time ON content_mutations(created_at);
CREATE TABLE content_write_limits (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  writes INTEGER NOT NULL DEFAULT 1,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE content_review_history (
  id BIGSERIAL PRIMARY KEY,
  content_id UUID NOT NULL REFERENCES content_items(id) ON DELETE CASCADE,
  content_version INTEGER NOT NULL,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action VARCHAR(24) NOT NULL CHECK(action IN ('created','updated','approved','changes_requested','published','withdrawn','archived')),
  note VARCHAR(1500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE FUNCTION bump_content_catalog_revision() RETURNS TRIGGER AS $$
BEGIN
  UPDATE content_catalog_state SET revision=revision+1,updated_at=NOW() WHERE singleton=TRUE;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_content_catalog_revision AFTER INSERT OR UPDATE OR DELETE ON content_items
  FOR EACH STATEMENT EXECUTE FUNCTION bump_content_catalog_revision();
