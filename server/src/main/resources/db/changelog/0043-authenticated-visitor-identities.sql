ALTER TABLE raw_event ADD COLUMN user_id_hash VARCHAR(64);
ALTER TABLE analytics_session ADD COLUMN user_id_hash VARCHAR(64);
CREATE INDEX idx_analytics_session_site_user_id_hash
  ON analytics_session(site_id,user_id_hash,started_at)
  WHERE user_id_hash IS NOT NULL;
