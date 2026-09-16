CREATE TABLE goal_definition (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  name VARCHAR(256) NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  trigger_type VARCHAR(32) NOT NULL CHECK (trigger_type IN ('event', 'page_view')),
  event_type VARCHAR(64),
  event_name VARCHAR(256),
  path_pattern VARCHAR(2048),
  path_match_mode VARCHAR(16) NOT NULL DEFAULT 'exact' CHECK (path_match_mode IN ('exact', 'contains')),
  fixed_value NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (fixed_value >= 0),
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (site_id, name),
  CHECK ((trigger_type = 'event' AND event_type IS NOT NULL AND path_pattern IS NULL)
      OR (trigger_type = 'page_view' AND event_type IS NULL AND event_name IS NULL AND path_pattern IS NOT NULL))
);

CREATE INDEX goal_definition_site_enabled_idx ON goal_definition(site_id, enabled);

CREATE TABLE analytics_goal_conversion_daily (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  goal_id UUID NOT NULL REFERENCES goal_definition(id) ON DELETE CASCADE,
  conversion_count BIGINT NOT NULL CHECK (conversion_count >= 0),
  converted_session_count BIGINT NOT NULL CHECK (converted_session_count >= 0),
  value_sum NUMERIC(18,4) NOT NULL CHECK (value_sum >= 0),
  PRIMARY KEY (site_id, business_date, goal_id)
);
