-- M11 Phase 2: learn from what she opens and finishes, and let her pick topics/formats.
-- Aggregates only (counts, seconds, last reason code); no raw event stream is stored.

ALTER TABLE content_views ADD COLUMN IF NOT EXISTS media_opens INTEGER NOT NULL DEFAULT 0 CHECK (media_opens >= 0);
ALTER TABLE content_views ADD COLUMN IF NOT EXISTS completions INTEGER NOT NULL DEFAULT 0 CHECK (completions >= 0);
ALTER TABLE content_views ADD COLUMN IF NOT EXISTS engaged_seconds INTEGER NOT NULL DEFAULT 0 CHECK (engaged_seconds BETWEEN 0 AND 10000000);
ALTER TABLE content_views ADD COLUMN IF NOT EXISTS last_engaged_at TIMESTAMPTZ;
-- Which recommendation reason was on the card when she opened it (Phase 3 reporting).
ALTER TABLE content_views ADD COLUMN IF NOT EXISTS last_reason VARCHAR(24) CHECK (last_reason IS NULL OR last_reason ~ '^[a-z_]{1,24}$');
-- Views can now be created by an engagement event before a detail open.
ALTER TABLE content_views ALTER COLUMN view_count SET DEFAULT 0;
ALTER TABLE content_views DROP CONSTRAINT IF EXISTS content_views_view_count_check;
ALTER TABLE content_views ADD CONSTRAINT content_views_view_count_check CHECK (view_count >= 0);
CREATE INDEX IF NOT EXISTS idx_content_views_reason ON content_views(last_reason) WHERE last_reason IS NOT NULL;

ALTER TABLE content_preferences ADD COLUMN IF NOT EXISTS interests TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE content_preferences ADD COLUMN IF NOT EXISTS preferred_formats TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE content_preferences ADD CONSTRAINT content_preferences_interests_check CHECK (
  interests <@ ARRAY['sleep','calm','music','low_mood','anxiety','feeding','body_recovery','baby_bonding','relationships','faith','learning']::text[]);
ALTER TABLE content_preferences ADD CONSTRAINT content_preferences_formats_check CHECK (
  preferred_formats <@ ARRAY['article','audio','video','activity']::text[]);

UPDATE content_catalog_state
  SET weights = '{"affinity":15,"interest":25,"format":8,"explore_slots":1}'::jsonb || weights,
      policy_version = policy_version + 1, revision = revision + 1, updated_at = NOW()
  WHERE singleton AND NOT (weights ? 'affinity' AND weights ? 'interest' AND weights ? 'format' AND weights ? 'explore_slots');
ALTER TABLE content_catalog_state ALTER COLUMN weights SET DEFAULT
  '{"context":30,"helpful":18,"not_helpful":-25,"practice":12,"saved":5,"rotation":6,"category_cap":3,"profile":20,"repeat":-8,"novelty":4,"affinity":15,"interest":25,"format":8,"explore_slots":1}'::jsonb;
