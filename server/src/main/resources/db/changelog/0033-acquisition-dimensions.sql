ALTER TABLE analytics_session ADD COLUMN initial_utm_term VARCHAR(256);
ALTER TABLE analytics_session ADD COLUMN initial_utm_content VARCHAR(256);

ALTER TABLE analytics_traffic_daily DROP CONSTRAINT analytics_traffic_daily_channel_check;
ALTER TABLE analytics_traffic_daily ADD CONSTRAINT analytics_traffic_daily_channel_check
  CHECK (channel IN ('direct', 'referral', 'campaign', 'search_engine', 'social', 'ai_assistant'));
ALTER TABLE analytics_traffic_daily ADD COLUMN term VARCHAR(256) NOT NULL DEFAULT '';
ALTER TABLE analytics_traffic_daily ADD COLUMN content VARCHAR(256) NOT NULL DEFAULT '';
ALTER TABLE analytics_traffic_daily DROP CONSTRAINT analytics_traffic_daily_pkey;
ALTER TABLE analytics_traffic_daily ADD PRIMARY KEY
  (site_id, business_date, channel, source, medium, campaign, term, content);
