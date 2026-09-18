CREATE TABLE site_audit_log (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
  action VARCHAR(24) NOT NULL CHECK (action IN ('CREATE', 'UPDATE', 'DELETE', 'PUBLISH', 'DUPLICATE')),
  resource VARCHAR(40) NOT NULL,
  resource_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_site_audit_log_site_time ON site_audit_log(site_id, created_at DESC, id DESC);
