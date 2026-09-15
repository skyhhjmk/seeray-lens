CREATE TABLE heatmap_site_config (
  site_id UUID PRIMARY KEY REFERENCES site(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  sample_rate SMALLINT NOT NULL DEFAULT 10 CHECK (sample_rate BETWEEN 0 AND 100),
  raw_retention_days INTEGER NOT NULL DEFAULT 30 CHECK (raw_retention_days BETWEEN 1 AND 3650),
  aggregate_retention_days INTEGER NOT NULL DEFAULT 180 CHECK (aggregate_retention_days BETWEEN 30 AND 3650),
  config_version BIGINT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE heatmap_raw_batch (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  client_batch_id UUID NOT NULL,
  received_at TIMESTAMPTZ NOT NULL,
  payload JSONB NOT NULL,
  processed_at TIMESTAMPTZ,
  failure_reason VARCHAR(256),
  UNIQUE (site_id, client_batch_id)
);
CREATE INDEX heatmap_raw_batch_pending_idx ON heatmap_raw_batch (received_at) WHERE processed_at IS NULL;

CREATE TABLE heatmap_variant (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  page_url VARCHAR(4096) NOT NULL,
  page_hash VARCHAR(64) NOT NULL,
  layout_version VARCHAR(128) NOT NULL,
  target_id VARCHAR(128) NOT NULL,
  viewport_width INTEGER NOT NULL CHECK (viewport_width > 0),
  viewport_height INTEGER NOT NULL CHECK (viewport_height > 0),
  content_width INTEGER NOT NULL CHECK (content_width > 0),
  content_height INTEGER NOT NULL CHECK (content_height > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (site_id, page_hash, layout_version, target_id, viewport_width, viewport_height, content_width, content_height)
);

CREATE TABLE heatmap_instance_fact (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  page_instance_id UUID NOT NULL,
  variant_id UUID NOT NULL REFERENCES heatmap_variant(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  sample_rate SMALLINT NOT NULL,
  scroll_bins BYTEA NOT NULL DEFAULT '\\x',
  truncated BOOLEAN NOT NULL DEFAULT FALSE,
  dropped_count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (site_id, page_instance_id, variant_id)
);
CREATE TABLE heatmap_grid_daily (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  variant_id UUID NOT NULL REFERENCES heatmap_variant(id) ON DELETE CASCADE,
  event_type VARCHAR(8) NOT NULL CHECK (event_type IN ('click', 'move')),
  grid_x INTEGER NOT NULL, grid_y INTEGER NOT NULL, event_count BIGINT NOT NULL CHECK (event_count >= 0),
  PRIMARY KEY (site_id, business_date, variant_id, event_type, grid_x, grid_y)
);
CREATE TABLE heatmap_scroll_daily (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  variant_id UUID NOT NULL REFERENCES heatmap_variant(id) ON DELETE CASCADE,
  depth_bin SMALLINT NOT NULL CHECK (depth_bin BETWEEN 0 AND 99),
  reached_count BIGINT NOT NULL CHECK (reached_count >= 0),
  instance_count BIGINT NOT NULL CHECK (instance_count >= 0),
  PRIMARY KEY (site_id, business_date, variant_id, depth_bin)
);
