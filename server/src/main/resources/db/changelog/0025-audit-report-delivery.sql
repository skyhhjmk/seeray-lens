ALTER TABLE site_audit_log DROP CONSTRAINT site_audit_log_action_check;
ALTER TABLE site_audit_log ADD CONSTRAINT ck_site_audit_log_action
  CHECK (action IN ('CREATE', 'UPDATE', 'DELETE', 'PUBLISH', 'DUPLICATE', 'SEND_NOW'));
