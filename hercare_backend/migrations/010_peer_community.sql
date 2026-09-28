CREATE TABLE community_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  alias VARCHAR(80) NOT NULL UNIQUE,
  rules_version VARCHAR(30) NOT NULL,
  suspended BOOLEAN NOT NULL DEFAULT FALSE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE community_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id UUID NOT NULL REFERENCES users(id),
  title VARCHAR(160) NOT NULL,
  description VARCHAR(1500) NOT NULL,
  expert_name VARCHAR(100) NOT NULL,
  credentials VARCHAR(300) NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  cancelled BOOLEAN NOT NULL DEFAULT FALSE,
  CHECK (ends_at > starts_at AND ends_at <= starts_at + INTERVAL '8 hours')
);
CREATE INDEX community_sessions_start_idx ON community_sessions(starts_at DESC, id DESC);
CREATE TABLE community_content (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES community_members(id) ON DELETE CASCADE,
  parent_id UUID REFERENCES community_content(id) ON DELETE CASCADE,
  session_id UUID REFERENCES community_sessions(id),
  topic VARCHAR(30) NOT NULL CHECK (topic IN ('coping','recovery','family','bonding','medication')),
  title VARCHAR(160) NOT NULL DEFAULT '',
  body_encrypted TEXT,
  language VARCHAR(8) NOT NULL,
  status VARCHAR(15) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','published','removed','deleted')),
  moderation JSONB NOT NULL DEFAULT '{}',
  expert_answer BOOLEAN NOT NULL DEFAULT FALSE,
  client_request_id UUID NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (author_id, client_request_id)
);
CREATE INDEX community_feed_idx ON community_content(created_at DESC, id DESC) WHERE parent_id IS NULL AND status = 'published';
CREATE INDEX community_topic_idx ON community_content(topic, created_at DESC, id DESC) WHERE parent_id IS NULL AND status = 'published';
CREATE INDEX community_parent_idx ON community_content(parent_id, created_at DESC, id DESC);
CREATE INDEX community_author_idx ON community_content(author_id, created_at DESC, id DESC);
CREATE INDEX community_pending_idx ON community_content(created_at DESC, id DESC) WHERE status = 'pending';
CREATE INDEX community_session_idx ON community_content(session_id, created_at DESC, id DESC);
CREATE TABLE community_reactions (
  content_id UUID NOT NULL REFERENCES community_content(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES community_members(id) ON DELETE CASCADE,
  kind VARCHAR(15) NOT NULL CHECK (kind IN ('heart','hug','support','solidarity')),
  PRIMARY KEY (content_id, member_id, kind)
);
CREATE TABLE community_blocks (
  blocker_id UUID NOT NULL REFERENCES community_members(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES community_members(id) ON DELETE CASCADE,
  PRIMARY KEY (blocker_id, blocked_id), CHECK (blocker_id <> blocked_id)
);
CREATE INDEX community_blocks_reverse_idx ON community_blocks(blocked_id, blocker_id);
CREATE TABLE community_reports (
  content_id UUID NOT NULL REFERENCES community_content(id) ON DELETE CASCADE,
  reporter_id UUID NOT NULL REFERENCES community_members(id) ON DELETE CASCADE,
  reason VARCHAR(25) NOT NULL CHECK (reason IN ('bullying','self_harm','spam','privacy','medical_advice','other')),
  resolved BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (content_id, reporter_id)
);
CREATE INDEX community_reports_open_idx ON community_reports(content_id) WHERE resolved = FALSE;
CREATE TABLE community_moderation_audit (
  id BIGSERIAL PRIMARY KEY,
  moderator_id UUID REFERENCES users(id) ON DELETE SET NULL,
  content_id UUID REFERENCES community_content(id) ON DELETE SET NULL,
  member_id UUID REFERENCES community_members(id) ON DELETE SET NULL,
  action VARCHAR(30) NOT NULL,
  reason VARCHAR(500) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Shared across API replicas; row locking enforces per-account write quotas.
CREATE TABLE community_write_limits (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  writes INTEGER NOT NULL DEFAULT 0
);
