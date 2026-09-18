CREATE TABLE analytics_microsoft_ads_capi_config (
  site_id UUID PRIMARY KEY REFERENCES site(id) ON DELETE CASCADE,
  tag_id VARCHAR(32) NOT NULL CHECK (tag_id ~ '^[0-9]{1,32}$'),
  currency_code CHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  api_token_ciphertext BYTEA NOT NULL,
  updated_by UUID NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE analytics_microsoft_ads_goal_mapping (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  goal_id UUID NOT NULL REFERENCES goal_definition(id) ON DELETE CASCADE,
  event_name VARCHAR(128) NOT NULL,
  updated_by UUID NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (site_id, goal_id),
  CHECK (length(trim(event_name)) > 0)
);
