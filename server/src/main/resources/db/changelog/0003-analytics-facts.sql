ALTER TABLE raw_event ADD COLUMN client_visitor_id VARCHAR(64);
ALTER TABLE raw_event ADD COLUMN client_session_id VARCHAR(64);
CREATE INDEX idx_raw_event_site_visitor_time ON raw_event(site_id, client_visitor_id, occurred_at);
CREATE INDEX idx_raw_event_site_session_time ON raw_event(site_id, client_session_id, occurred_at);
CREATE TABLE analytics_visitor (
  id UUID PRIMARY KEY, site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  client_visitor_id VARCHAR(64) NOT NULL, first_seen_at TIMESTAMPTZ NOT NULL, last_seen_at TIMESTAMPTZ NOT NULL,
  first_session_at TIMESTAMPTZ, last_session_at TIMESTAMPTZ, session_count INTEGER NOT NULL DEFAULT 0 CHECK (session_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(site_id, client_visitor_id)
);
CREATE TABLE analytics_session (
  id UUID PRIMARY KEY, site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  visitor_id UUID NOT NULL REFERENCES analytics_visitor(id) ON DELETE CASCADE, client_session_id VARCHAR(64) NOT NULL,
  started_at TIMESTAMPTZ NOT NULL, last_activity_at TIMESTAMPTZ NOT NULL, ended_at TIMESTAMPTZ,
  entry_page VARCHAR(2048), exit_page VARCHAR(2048), page_view_count INTEGER NOT NULL DEFAULT 0 CHECK (page_view_count >= 0),
  event_count INTEGER NOT NULL DEFAULT 0 CHECK (event_count >= 0), duration_ms BIGINT NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
  is_bounce BOOLEAN NOT NULL DEFAULT true, visitor_type VARCHAR(16) NOT NULL CHECK (visitor_type IN ('new','returning')),
  initial_referrer_host VARCHAR(253), initial_utm_source VARCHAR(256), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_analytics_session_site_started ON analytics_session(site_id, started_at);
CREATE INDEX idx_analytics_session_visitor ON analytics_session(visitor_id, started_at);
CREATE TABLE visitor_day_fact (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE, business_date DATE NOT NULL,
  visitor_id UUID NOT NULL REFERENCES analytics_visitor(id) ON DELETE CASCADE,
  PRIMARY KEY(site_id, business_date, visitor_id)
);
CREATE TABLE analytics_fact_checkpoint (
  site_id UUID PRIMARY KEY REFERENCES site(id) ON DELETE CASCADE,
  last_received_at TIMESTAMPTZ NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
