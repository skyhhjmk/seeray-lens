CREATE INDEX idx_raw_event_site_crash_occurred
  ON raw_event(site_id, occurred_at DESC)
  WHERE event_type = 'client_error';
