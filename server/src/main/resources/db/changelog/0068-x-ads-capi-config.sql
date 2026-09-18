CREATE TABLE analytics_x_ads_capi_config (
  site_id UUID PRIMARY KEY REFERENCES site(id) ON DELETE CASCADE,
  pixel_id VARCHAR(256) NOT NULL,
  currency_code CHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  access_token_ciphertext BYTEA NOT NULL,
  updated_by UUID NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE analytics_x_ads_goal_mapping (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  goal_id UUID NOT NULL REFERENCES goal_definition(id) ON DELETE CASCADE,
  event_id VARCHAR(256) NOT NULL,
  updated_by UUID NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (site_id, goal_id),
  CHECK (length(trim(event_id)) > 0)
);

ALTER TABLE site_audit_log DROP CONSTRAINT ck_site_audit_log_action;

ALTER TABLE site_audit_log ADD CONSTRAINT ck_site_audit_log_action
  CHECK (action IN (
    'CREATE', 'UPDATE', 'DELETE', 'PUBLISH', 'DUPLICATE', 'SEND_NOW',
    'REQUEST_PRODUCTION', 'APPROVE_PRODUCTION', 'REJECT_PRODUCTION',
    'CANCEL_PRODUCTION', 'IMPORT', 'SEND_TO_GOOGLE_ADS',
    'SEND_TO_MICROSOFT_ADS', 'SEND_TO_META_ADS', 'SEND_TO_LINKEDIN_ADS',
    'SEND_TO_X_ADS'
  ));
