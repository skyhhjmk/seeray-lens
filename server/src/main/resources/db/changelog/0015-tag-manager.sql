CREATE TABLE tag_container (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  name VARCHAR(256) NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  published_version INTEGER,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (site_id, name)
);

CREATE TABLE tag_container_version (
  id UUID PRIMARY KEY,
  container_id UUID NOT NULL REFERENCES tag_container(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  status VARCHAR(16) NOT NULL CHECK (status IN ('draft', 'published')),
  tags_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  UNIQUE (container_id, version)
);

CREATE INDEX tag_container_site_idx ON tag_container(site_id, enabled);
