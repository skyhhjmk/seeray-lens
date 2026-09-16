CREATE TABLE experiment_definition (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  name VARCHAR(256) NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  variants_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (site_id, name),
  CHECK (jsonb_typeof(variants_json) = 'array')
);

CREATE INDEX experiment_definition_site_idx ON experiment_definition(site_id, enabled);
