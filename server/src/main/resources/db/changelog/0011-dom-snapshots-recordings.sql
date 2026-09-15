ALTER TABLE heatmap_site_config
  ADD COLUMN auto_snapshot_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN recording_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN recording_sample_rate SMALLINT NOT NULL DEFAULT 1 CHECK (recording_sample_rate BETWEEN 0 AND 100),
  ADD COLUMN recording_retention_days INTEGER NOT NULL DEFAULT 14 CHECK (recording_retention_days BETWEEN 1 AND 365);

CREATE TABLE heatmap_dom_snapshot (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  variant_id UUID NOT NULL REFERENCES heatmap_variant(id) ON DELETE CASCADE,
  source_instance_id UUID NOT NULL,
  protocol_version INTEGER NOT NULL,
  payload JSONB NOT NULL,
  payload_bytes INTEGER NOT NULL CHECK (payload_bytes > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (variant_id)
);
CREATE INDEX heatmap_dom_snapshot_site_idx ON heatmap_dom_snapshot (site_id, created_at DESC);

CREATE TABLE session_recording (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  page_count INTEGER NOT NULL DEFAULT 0 CHECK (page_count >= 0),
  event_count INTEGER NOT NULL DEFAULT 0 CHECK (event_count >= 0),
  byte_count BIGINT NOT NULL DEFAULT 0 CHECK (byte_count >= 0),
  truncated BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX session_recording_site_started_idx ON session_recording (site_id, started_at DESC);
CREATE INDEX session_recording_expiry_idx ON session_recording (expires_at);

CREATE TABLE session_recording_chunk (
  recording_id UUID NOT NULL REFERENCES session_recording(id) ON DELETE CASCADE,
  sequence INTEGER NOT NULL CHECK (sequence >= 0),
  page_instance_id UUID NOT NULL,
  page_url VARCHAR(4096) NOT NULL,
  protocol_version INTEGER NOT NULL,
  payload JSONB NOT NULL,
  payload_bytes INTEGER NOT NULL CHECK (payload_bytes > 0),
  event_count INTEGER NOT NULL CHECK (event_count > 0),
  started_offset_ms INTEGER NOT NULL CHECK (started_offset_ms >= 0),
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (recording_id, page_instance_id, sequence)
);
