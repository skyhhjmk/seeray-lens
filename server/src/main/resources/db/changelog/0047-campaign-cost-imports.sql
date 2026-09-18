CREATE TABLE analytics_campaign_cost_import (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  file_name VARCHAR(255) NOT NULL,
  file_hash VARCHAR(64) NOT NULL,
  row_count INTEGER NOT NULL CHECK (row_count > 0),
  actor_user_id UUID NOT NULL,
  imported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (site_id, file_hash)
);

CREATE TABLE analytics_campaign_cost (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  platform VARCHAR(32) NOT NULL,
  source VARCHAR(128) NOT NULL,
  medium VARCHAR(128) NOT NULL,
  campaign VARCHAR(256) NOT NULL,
  currency CHAR(3) NOT NULL,
  impressions BIGINT NOT NULL CHECK (impressions >= 0),
  clicks BIGINT NOT NULL CHECK (clicks >= 0),
  cost_amount NUMERIC(18,6) NOT NULL CHECK (cost_amount >= 0),
  import_id UUID NOT NULL REFERENCES analytics_campaign_cost_import(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (site_id, business_date, platform, source, medium, campaign, currency)
);

CREATE INDEX idx_analytics_campaign_cost_site_date
  ON analytics_campaign_cost(site_id, business_date);
CREATE INDEX idx_analytics_campaign_cost_campaign
  ON analytics_campaign_cost(site_id, source, medium, campaign, business_date);
