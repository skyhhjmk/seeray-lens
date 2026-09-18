CREATE TABLE analytics_alert (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL,
  metric VARCHAR(16) NOT NULL CHECK (metric IN ('visitors', 'sessions', 'page_views', 'bounce_rate')),
  direction VARCHAR(12) NOT NULL CHECK (direction IN ('increase', 'decrease')),
  baseline VARCHAR(24) NOT NULL CHECK (baseline IN ('previous_day', 'same_weekday_last_week')),
  threshold_percent NUMERIC(8,2) NOT NULL CHECK (threshold_percent > 0 AND threshold_percent <= 1000),
  local_time TIME NOT NULL,
  timezone VARCHAR(80) NOT NULL,
  channels TEXT[] NOT NULL,
  recipients TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  last_evaluated_date DATE,
  last_evaluated_at TIMESTAMPTZ,
  last_status VARCHAR(12) CHECK (last_status IN ('triggered', 'unchanged', 'failed')),
  last_message VARCHAR(240),
  last_value NUMERIC(18,4),
  last_change_percent NUMERIC(12,2),
  last_baseline_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (cardinality(channels) BETWEEN 1 AND 3),
  CHECK (channels <@ ARRAY['email', 'slack', 'teams']::TEXT[]),
  CHECK (
    ('email' = ANY(channels) AND cardinality(recipients) BETWEEN 1 AND 10)
    OR ('email' <> ALL(channels) AND cardinality(recipients) = 0)
  )
);
CREATE INDEX idx_analytics_alert_site ON analytics_alert(site_id, created_at);
