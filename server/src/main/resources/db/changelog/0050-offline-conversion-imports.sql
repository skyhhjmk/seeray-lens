CREATE TABLE analytics_offline_conversion_import (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  goal_id UUID NOT NULL REFERENCES goal_definition(id) ON DELETE CASCADE,
  file_hash VARCHAR(64) NOT NULL,
  row_count INTEGER NOT NULL CHECK (row_count > 0),
  actor_user_id UUID NOT NULL,
  imported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (site_id, goal_id, file_hash)
);

CREATE TABLE analytics_offline_conversion (
  id UUID PRIMARY KEY,
  import_id UUID NOT NULL REFERENCES analytics_offline_conversion_import(id) ON DELETE CASCADE,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  goal_id UUID NOT NULL REFERENCES goal_definition(id) ON DELETE CASCADE,
  conversion_key_hash VARCHAR(64) NOT NULL,
  ad_click_platform VARCHAR(32) NOT NULL,
  ad_click_id_hash VARCHAR(64) NOT NULL,
  converted_at TIMESTAMPTZ NOT NULL,
  UNIQUE (site_id, conversion_key_hash)
);

CREATE INDEX idx_analytics_offline_conversion_click
  ON analytics_offline_conversion(site_id, ad_click_platform, ad_click_id_hash, converted_at);
CREATE INDEX idx_analytics_offline_conversion_date
  ON analytics_offline_conversion(site_id, converted_at, goal_id);
