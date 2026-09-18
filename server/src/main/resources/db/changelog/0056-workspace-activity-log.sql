CREATE TABLE workspace_audit_log (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
  action VARCHAR(32) NOT NULL CHECK (action IN (
    'CREATE_WORKSPACE',
    'UPDATE_WORKSPACE',
    'CREATE_SITE',
    'ADD_MEMBER',
    'CHANGE_ROLE',
    'REMOVE_MEMBER',
    'TRANSFER_OWNERSHIP',
    'CREATE_INVITATION',
    'REVOKE_INVITATION',
    'ACCEPT_INVITATION',
    'CREATE_API_TOKEN',
    'REVOKE_API_TOKEN'
  )),
  resource VARCHAR(32) NOT NULL,
  resource_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_workspace_audit_log_org_time
  ON workspace_audit_log(organization_id, created_at DESC, id DESC);
