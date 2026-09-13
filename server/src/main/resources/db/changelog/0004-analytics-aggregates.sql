CREATE TABLE analytics_site_daily (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  page_view_count BIGINT NOT NULL DEFAULT 0 CHECK (page_view_count >= 0),
  session_count BIGINT NOT NULL DEFAULT 0 CHECK (session_count >= 0),
  new_session_count BIGINT NOT NULL DEFAULT 0 CHECK (new_session_count >= 0),
  returning_session_count BIGINT NOT NULL DEFAULT 0 CHECK (returning_session_count >= 0),
  bounced_session_count BIGINT NOT NULL DEFAULT 0 CHECK (bounced_session_count >= 0),
  session_duration_sum_ms BIGINT NOT NULL DEFAULT 0 CHECK (session_duration_sum_ms >= 0),
  session_duration_count BIGINT NOT NULL DEFAULT 0 CHECK (session_duration_count >= 0),
  PRIMARY KEY (site_id, business_date)
);
CREATE TABLE analytics_page_daily (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  path VARCHAR(2048) NOT NULL,
  page_view_count BIGINT NOT NULL CHECK (page_view_count >= 0),
  PRIMARY KEY (site_id, business_date, path)
);
CREATE TABLE analytics_traffic_daily (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  channel VARCHAR(16) NOT NULL CHECK (channel IN ('direct', 'referral', 'campaign')),
  source VARCHAR(256), medium VARCHAR(256), campaign VARCHAR(256),
  session_count BIGINT NOT NULL CHECK (session_count >= 0),
  PRIMARY KEY (site_id, business_date, channel, source, medium, campaign)
);
CREATE TABLE analytics_event_daily (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  event_type VARCHAR(64) NOT NULL,
  event_count BIGINT NOT NULL CHECK (event_count >= 0),
  PRIMARY KEY (site_id, business_date, event_type)
);
ALTER TABLE analytics_session ADD COLUMN initial_page_host VARCHAR(253);
ALTER TABLE analytics_session ADD COLUMN initial_utm_medium VARCHAR(256);
ALTER TABLE analytics_session ADD COLUMN initial_utm_campaign VARCHAR(256);
