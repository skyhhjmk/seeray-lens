ALTER TABLE site
    ADD COLUMN fingerprint_risk_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN fingerprint_retention_days INTEGER NOT NULL DEFAULT 30;

CREATE TABLE fingerprint_observation (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  client_visitor_id VARCHAR(64) NOT NULL,
  client_session_id VARCHAR(64) NOT NULL,
  fingerprint_key VARCHAR(64) NOT NULL,
  algorithm_version INTEGER NOT NULL,
  signal_stability VARCHAR(16) NOT NULL,
  user_id_hash VARCHAR(64),
  observed_at TIMESTAMPTZ NOT NULL,
  CHECK (fingerprint_key ~ '^[0-9a-f]{64}$'),
  CHECK (signal_stability IN ('high', 'medium', 'low'))
);

CREATE INDEX idx_fingerprint_observation_site_key
  ON fingerprint_observation(site_id, fingerprint_key, observed_at);
CREATE INDEX idx_fingerprint_observation_site_visitor
  ON fingerprint_observation(site_id, client_visitor_id, observed_at);
CREATE INDEX idx_fingerprint_observation_expiry
  ON fingerprint_observation(site_id, observed_at);
