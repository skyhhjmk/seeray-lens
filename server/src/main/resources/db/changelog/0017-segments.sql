CREATE TABLE segment_definition (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  name VARCHAR(128) NOT NULL,
  description VARCHAR(512) NOT NULL DEFAULT '',
  match_mode VARCHAR(8) NOT NULL CHECK (match_mode IN ('all','any')),
  rules_json JSONB NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (site_id, name),
  CHECK (jsonb_typeof(rules_json) = 'array')
);

CREATE INDEX segment_definition_site_idx ON segment_definition(site_id, enabled, name);
