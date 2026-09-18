CREATE INDEX idx_raw_event_site_media_occurred
  ON raw_event(site_id, occurred_at)
  WHERE event_type IN ('media_start','media_progress','media_complete');
