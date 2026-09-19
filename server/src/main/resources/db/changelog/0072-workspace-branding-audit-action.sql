ALTER TABLE workspace_audit_log
  DROP CONSTRAINT workspace_audit_log_action_check;

ALTER TABLE workspace_audit_log
  ADD CONSTRAINT workspace_audit_log_action_check CHECK (action IN (
    'CREATE_WORKSPACE',
    'UPDATE_WORKSPACE',
    'UPDATE_WORKSPACE_BRANDING',
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
  ));
