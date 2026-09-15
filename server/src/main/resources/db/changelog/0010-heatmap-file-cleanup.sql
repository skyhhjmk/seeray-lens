CREATE TABLE heatmap_file_cleanup (
  file_key VARCHAR(128) PRIMARY KEY,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
