CREATE TABLE workspace_extension (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  extension_key VARCHAR(80) NOT NULL,
  name VARCHAR(160) NOT NULL,
  version VARCHAR(32) NOT NULL,
  endpoint_url VARCHAR(2048) NOT NULL,
  subscriptions_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  secret_encrypted BYTEA NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'enabled' CHECK (status IN ('enabled', 'disabled', 'archived')),
  created_by UUID NOT NULL REFERENCES app_user(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, extension_key),
  CHECK (jsonb_typeof(subscriptions_json) = 'array')
);

CREATE INDEX idx_workspace_extension_org_status
  ON workspace_extension(organization_id, status, updated_at DESC);
