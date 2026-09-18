ALTER TABLE raw_event ADD COLUMN ad_click_platform VARCHAR(32);
ALTER TABLE raw_event ADD COLUMN ad_click_id_hash VARCHAR(64);
ALTER TABLE analytics_session ADD COLUMN ad_click_platform VARCHAR(32);
ALTER TABLE analytics_session ADD COLUMN ad_click_id_hash VARCHAR(64);

CREATE INDEX idx_raw_event_ad_click_hash
  ON raw_event(site_id, ad_click_platform, ad_click_id_hash)
  WHERE ad_click_id_hash IS NOT NULL;
CREATE INDEX idx_analytics_session_ad_click_hash
  ON analytics_session(site_id, ad_click_platform, ad_click_id_hash)
  WHERE ad_click_id_hash IS NOT NULL;
