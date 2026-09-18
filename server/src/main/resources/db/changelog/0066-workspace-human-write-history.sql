CREATE TABLE workspace_api_write_log (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
  site_id UUID REFERENCES site(id) ON DELETE SET NULL,
  method VARCHAR(8) NOT NULL CHECK (method IN ('POST', 'PUT', 'PATCH', 'DELETE')),
  route_template VARCHAR(512) NOT NULL,
  status_code INTEGER NOT NULL CHECK (status_code BETWEEN 200 AND 299),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_workspace_api_write_log_org_time
  ON workspace_api_write_log(organization_id, created_at DESC, id DESC);
