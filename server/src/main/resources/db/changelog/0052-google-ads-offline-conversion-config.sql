CREATE TABLE analytics_google_ads_conversion_config (
  site_id UUID PRIMARY KEY REFERENCES site(id) ON DELETE CASCADE,
  customer_id VARCHAR(20) NOT NULL,
  login_customer_id VARCHAR(20),
  conversion_action_id VARCHAR(32) NOT NULL,
  currency_code CHAR(3) NOT NULL,
  updated_by UUID NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (customer_id ~ '^[0-9]{6,20}$'),
  CHECK (login_customer_id IS NULL OR login_customer_id ~ '^[0-9]{6,20}$'),
  CHECK (conversion_action_id ~ '^[0-9]{1,32}$'),
  CHECK (currency_code ~ '^[A-Z]{3}$')
);
