ALTER TABLE api_token
  ADD COLUMN created_by_user_id UUID;

UPDATE api_token token
SET created_by_user_id = owner.user_id
FROM (
  SELECT DISTINCT ON (organization_id) organization_id, user_id
  FROM organization_member
  WHERE role = 'OWNER'
  ORDER BY organization_id, user_id
) owner
WHERE token.organization_id = owner.organization_id;

ALTER TABLE api_token
  ALTER COLUMN created_by_user_id SET NOT NULL,
  ADD CONSTRAINT fk_api_token_created_by
    FOREIGN KEY (created_by_user_id) REFERENCES app_user(id) ON DELETE CASCADE;

CREATE INDEX idx_api_token_workspace_actor
  ON api_token(organization_id, created_by_user_id, revoked_at);

ALTER TABLE workspace_audit_log
  ADD COLUMN actor_api_token_id UUID REFERENCES api_token(id) ON DELETE SET NULL;

ALTER TABLE site_audit_log
  ADD COLUMN actor_api_token_id UUID REFERENCES api_token(id) ON DELETE SET NULL;
