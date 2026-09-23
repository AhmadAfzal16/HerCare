-- HerCare Database Migration 001
-- Initial schema: users, refresh_tokens, onboarding_data
-- Run: psql -U hercare_user -d hercare_db -f migrations/001_initial_schema.sql

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── Users ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone                 VARCHAR(15)  NOT NULL UNIQUE,        -- +92XXXXXXXXXX
  password_hash         TEXT         NOT NULL,
  role                  VARCHAR(10)  NOT NULL DEFAULT 'mother'
                          CHECK (role IN ('mother', 'guardian', 'admin')),
  language              VARCHAR(5)   NOT NULL DEFAULT 'en'
                          CHECK (language IN ('en', 'ur')),
  is_active             BOOLEAN      NOT NULL DEFAULT TRUE,
  onboarding_complete   BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);

-- ─── Refresh Tokens ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT         NOT NULL,         -- bcrypt hash; never store plaintext
  expires_at  TIMESTAMPTZ  NOT NULL,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires  ON refresh_tokens(expires_at);

-- ─── Onboarding Data ──────────────────────────────────────────────────────────
-- Stores all 4 onboarding steps. Fields match PERI_DEP dataset columns
-- for direct ML feature extraction in Phase 1 M4.
CREATE TABLE IF NOT EXISTS onboarding_data (
  id                         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                    UUID         NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

  -- Step 1: Personal
  full_name                  VARCHAR(100),
  age                        SMALLINT     CHECK (age BETWEEN 15 AND 55),
  education_level            VARCHAR(50),
  city                       VARCHAR(60),
  months_since_birth         SMALLINT     CHECK (months_since_birth BETWEEN 0 AND 12),

  -- Step 2: Obstetric (ML risk features)
  delivery_method            VARCHAR(10)  CHECK (delivery_method IN ('vaginal', 'cesarean')),
  parity                     SMALLINT     NOT NULL DEFAULT 0,
  baby_gender                VARCHAR(6)   CHECK (baby_gender IN ('male', 'female')),
  has_preeclampsia           BOOLEAN      NOT NULL DEFAULT FALSE,
  has_postpartum_hemorrhage  BOOLEAN      NOT NULL DEFAULT FALSE,
  has_preterm_birth          BOOLEAN      NOT NULL DEFAULT FALSE,
  has_gestational_diabetes   BOOLEAN      NOT NULL DEFAULT FALSE,

  -- Step 3: Family / Social
  household_type             VARCHAR(10)  CHECK (household_type IN ('nuclear', 'joint')),
  income_range               VARCHAR(50),
  primary_support            VARCHAR(15)  CHECK (primary_support IN ('husband', 'mother_in_law', 'siblings', 'none')),

  -- Step 4: Consent
  consent_tier1              BOOLEAN      NOT NULL DEFAULT TRUE,
  consent_tier2              BOOLEAN      NOT NULL DEFAULT TRUE,
  consent_tier3              BOOLEAN      NOT NULL DEFAULT FALSE,

  created_at                 TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at                 TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─── Guardian Links ───────────────────────────────────────────────────────────
-- Secure invitation-based linking (Phase 1 M2)
CREATE TABLE IF NOT EXISTS guardian_links (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  guardian_id   UUID        REFERENCES users(id) ON DELETE SET NULL,
  invite_code   VARCHAR(12) UNIQUE,                    -- 12-char random code
  status        VARCHAR(10) NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'active', 'revoked')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_guardian_links_mother   ON guardian_links(mother_id);
CREATE INDEX IF NOT EXISTS idx_guardian_links_guardian ON guardian_links(guardian_id);
CREATE INDEX IF NOT EXISTS idx_guardian_links_code     ON guardian_links(invite_code);

-- ─── Updated-at trigger ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_onboarding_updated_at ON onboarding_data;
CREATE TRIGGER trg_onboarding_updated_at
  BEFORE UPDATE ON onboarding_data
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── Cleanup job: expired refresh tokens ──────────────────────────────────────
-- Run this periodically via pg_cron or a scheduled task:
-- DELETE FROM refresh_tokens WHERE expires_at < NOW();
