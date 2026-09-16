CREATE TABLE funnel_definition (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  name VARCHAR(256) NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  steps_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (site_id, name),
  CHECK (jsonb_typeof(steps_json) = 'array')
);

CREATE INDEX funnel_definition_site_idx ON funnel_definition(site_id, enabled);
