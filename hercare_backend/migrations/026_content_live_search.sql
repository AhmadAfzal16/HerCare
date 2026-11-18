-- M11 live YouTube search: shared per-topic cache (no personal data) and per-account hides.
CREATE TABLE IF NOT EXISTS content_live_cache (
  topic VARCHAR(24) NOT NULL CHECK (topic ~ '^[a-z_]{1,24}$'),
  language VARCHAR(2) NOT NULL CHECK (language IN ('en','ur')),
  items JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(items) = 'array' AND jsonb_array_length(items) <= 12),
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (topic, language)
);
CREATE TABLE IF NOT EXISTS content_live_hidden (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  video_id VARCHAR(11) NOT NULL CHECK (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, video_id)
);
CREATE INDEX IF NOT EXISTS idx_content_live_hidden_video ON content_live_hidden(video_id);
