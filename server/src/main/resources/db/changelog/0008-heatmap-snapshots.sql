CREATE TABLE heatmap_snapshot (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  variant_id UUID NOT NULL REFERENCES heatmap_variant(id) ON DELETE CASCADE,
  file_key VARCHAR(128) NOT NULL UNIQUE,
  content_type VARCHAR(32) NOT NULL,
  image_width INTEGER NOT NULL,
  image_height INTEGER NOT NULL,
  image_hash VARCHAR(64) NOT NULL,
  uploaded_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX heatmap_snapshot_variant_idx ON heatmap_snapshot (variant_id, created_at DESC);
