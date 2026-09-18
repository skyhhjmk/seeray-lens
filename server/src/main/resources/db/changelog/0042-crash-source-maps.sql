CREATE TABLE crash_source_map (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  release_id VARCHAR(100) NOT NULL,
  bundle_path VARCHAR(1024) NOT NULL,
  source_count INTEGER NOT NULL CHECK (source_count BETWEEN 1 AND 10000),
  map_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (site_id, release_id, bundle_path),
  CHECK (jsonb_typeof(map_json) = 'object')
);
