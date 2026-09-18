CREATE TABLE tag_manager_preview_session (
  id UUID PRIMARY KEY,
  container_id UUID NOT NULL REFERENCES tag_container(id) ON DELETE CASCADE,
  token_hash CHAR(64) NOT NULL,
  tags_json JSONB NOT NULL,
  execute_custom_code BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX tag_manager_preview_session_container_idx
  ON tag_manager_preview_session(container_id, expires_at);

CREATE TABLE tag_manager_preview_event (
  id UUID PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES tag_manager_preview_session(id) ON DELETE CASCADE,
  tag_index INTEGER NOT NULL CHECK (tag_index BETWEEN 0 AND 99),
  tag_name VARCHAR(256) NOT NULL,
  trigger_event VARCHAR(64) NOT NULL,
  outcome VARCHAR(16) NOT NULL CHECK (outcome IN ('fired', 'no_match', 'blocked')),
  page_path VARCHAR(512) NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX tag_manager_preview_event_session_idx
  ON tag_manager_preview_event(session_id, occurred_at DESC);
