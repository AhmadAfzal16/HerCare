-- M11 live search, part 2: a daily library of recent uploads from trusted channels only.
-- Public video metadata only; no personal data.
CREATE TABLE IF NOT EXISTS content_live_library (
  video_id VARCHAR(11) PRIMARY KEY CHECK (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  channel_id VARCHAR(24) NOT NULL CHECK (channel_id ~ '^UC[A-Za-z0-9_-]{22}$'),
  kind VARCHAR(10) NOT NULL CHECK (kind IN ('health','calm','music','faith')),
  title VARCHAR(200) NOT NULL,
  published_at TIMESTAMPTZ,
  duration_seconds INTEGER NOT NULL CHECK (duration_seconds BETWEEN 60 AND 14400),
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_content_live_library_kind ON content_live_library(kind, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_live_library_channel ON content_live_library(channel_id);
CREATE TABLE IF NOT EXISTS content_live_channel_state (
  channel_id VARCHAR(24) PRIMARY KEY CHECK (channel_id ~ '^UC[A-Za-z0-9_-]{22}$'),
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ok BOOLEAN NOT NULL DEFAULT TRUE
);
