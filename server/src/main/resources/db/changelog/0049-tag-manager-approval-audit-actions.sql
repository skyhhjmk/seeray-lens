ALTER TABLE site_audit_log DROP CONSTRAINT ck_site_audit_log_action;

ALTER TABLE site_audit_log ADD CONSTRAINT ck_site_audit_log_action
  CHECK (action IN (
    'CREATE',
    'UPDATE',
    'DELETE',
    'PUBLISH',
    'DUPLICATE',
    'SEND_NOW',
    'REQUEST_PRODUCTION',
    'APPROVE_PRODUCTION',
    'REJECT_PRODUCTION',
    'CANCEL_PRODUCTION'
  ));
