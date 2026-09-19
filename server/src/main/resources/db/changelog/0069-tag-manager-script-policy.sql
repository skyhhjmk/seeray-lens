CREATE TABLE tag_container_security_policy (
  container_id UUID PRIMARY KEY REFERENCES tag_container(id) ON DELETE CASCADE,
  allow_custom_code BOOLEAN NOT NULL DEFAULT TRUE,
  allowed_script_origins_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_by UUID NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(allowed_script_origins_json) = 'array')
);
