ALTER TABLE analytics_session ADD COLUMN browser VARCHAR(32);
ALTER TABLE analytics_session ADD COLUMN browser_version VARCHAR(24);
ALTER TABLE analytics_session ADD COLUMN operating_system VARCHAR(32);
ALTER TABLE analytics_session ADD COLUMN operating_system_version VARCHAR(24);
ALTER TABLE analytics_session ADD COLUMN device_type VARCHAR(16);
ALTER TABLE analytics_session ADD COLUMN language VARCHAR(35);
ALTER TABLE analytics_session ADD COLUMN screen_width INTEGER;
ALTER TABLE analytics_session ADD COLUMN screen_height INTEGER;
ALTER TABLE analytics_session ADD COLUMN viewport_width INTEGER;
ALTER TABLE analytics_session ADD COLUMN viewport_height INTEGER;
ALTER TABLE analytics_session ADD COLUMN pixel_ratio DOUBLE PRECISION;

CREATE INDEX idx_analytics_session_site_technology ON analytics_session(site_id, started_at, browser, operating_system, device_type);
