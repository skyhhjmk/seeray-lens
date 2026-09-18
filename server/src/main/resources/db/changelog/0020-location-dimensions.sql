ALTER TABLE analytics_session ADD COLUMN country_code CHAR(2);
ALTER TABLE analytics_session ADD COLUMN continent_code CHAR(2);
ALTER TABLE analytics_session ADD COLUMN region_code VARCHAR(16);
ALTER TABLE analytics_session ADD COLUMN region_name VARCHAR(120);
ALTER TABLE analytics_session ADD COLUMN city VARCHAR(120);
ALTER TABLE analytics_session ADD COLUMN geo_timezone VARCHAR(64);

CREATE INDEX analytics_session_site_country_idx ON analytics_session(site_id, country_code);
