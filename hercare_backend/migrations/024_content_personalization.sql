-- M11 Phase 1 personalization: postpartum stage, 7-day trends and repeat damping.
-- Rules stay transparent; no new clinical prediction is introduced.

-- When months_since_birth was last entered, so the stage can advance over time.
-- consent toggles bump updated_at, so a dedicated timestamp is required.
ALTER TABLE onboarding_data ADD COLUMN IF NOT EXISTS months_since_birth_recorded_at TIMESTAMPTZ;
UPDATE onboarding_data SET months_since_birth_recorded_at = created_at WHERE months_since_birth_recorded_at IS NULL;
ALTER TABLE onboarding_data ALTER COLUMN months_since_birth_recorded_at SET DEFAULT NOW();
ALTER TABLE onboarding_data ALTER COLUMN months_since_birth_recorded_at SET NOT NULL;

-- Per-account open counts. IDs and timestamps only; deleted with the account or item.
CREATE TABLE IF NOT EXISTS content_views (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content_id UUID NOT NULL REFERENCES content_items(id) ON DELETE CASCADE,
  view_count INTEGER NOT NULL DEFAULT 1 CHECK (view_count > 0),
  first_viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, content_id)
);

-- New ranking weights. Existing operator-tuned values are kept.
UPDATE content_catalog_state
  SET weights = '{"profile":20,"repeat":-8,"novelty":4}'::jsonb || weights,
      policy_version = policy_version + 1, revision = revision + 1, updated_at = NOW()
  WHERE singleton AND NOT (weights ? 'profile' AND weights ? 'repeat' AND weights ? 'novelty');
ALTER TABLE content_catalog_state ALTER COLUMN weights SET DEFAULT
  '{"context":30,"helpful":18,"not_helpful":-25,"practice":12,"saved":5,"rotation":6,"category_cap":3,"profile":20,"repeat":-8,"novelty":4}'::jsonb;
