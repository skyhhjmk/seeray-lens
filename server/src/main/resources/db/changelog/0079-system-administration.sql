ALTER TABLE app_user
  ADD COLUMN is_system_admin BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN auth_version BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN must_change_password BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE app_user
SET is_system_admin = TRUE
WHERE id = (
  SELECT id FROM app_user ORDER BY created_at ASC, id ASC LIMIT 1
)
OR id = (
  SELECT id FROM app_user WHERE status = 'ACTIVE' ORDER BY created_at ASC, id ASC LIMIT 1
);

CREATE TABLE system_admin_audit (
  id UUID PRIMARY KEY,
  actor_user_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
  target_user_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
  site_id UUID,
  action VARCHAR(48) NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_system_admin_audit_created ON system_admin_audit(created_at DESC);
