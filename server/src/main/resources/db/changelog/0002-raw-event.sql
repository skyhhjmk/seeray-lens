CREATE TABLE raw_event (
  ingest_id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  client_event_id UUID NOT NULL,
  received_at TIMESTAMPTZ NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  event_type VARCHAR(64) NOT NULL,
  page_scheme VARCHAR(16), page_host VARCHAR(253), page_path VARCHAR(2048), page_title VARCHAR(512),
  referrer_scheme VARCHAR(16), referrer_host VARCHAR(253), referrer_path VARCHAR(2048),
  utm_source VARCHAR(256), utm_medium VARCHAR(256), utm_campaign VARCHAR(256),
  utm_term VARCHAR(256), utm_content VARCHAR(256),
  event_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  duration_ms INTEGER,
  ingest_version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(site_id, client_event_id),
  CHECK (duration_ms IS NULL OR duration_ms >= 0),
  CHECK (event_type <> '')
);
CREATE INDEX idx_raw_event_site_received ON raw_event(site_id, received_at);
CREATE INDEX idx_raw_event_site_occurred ON raw_event(site_id, occurred_at);
