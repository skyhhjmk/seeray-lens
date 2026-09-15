ALTER TABLE heatmap_raw_batch ADD COLUMN effective_sample_rate SMALLINT NOT NULL DEFAULT 10 CHECK (effective_sample_rate BETWEEN 0 AND 100);
