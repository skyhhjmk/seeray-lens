CREATE INDEX idx_raw_event_web_vitals_session_time
  ON raw_event(site_id, client_session_id, client_visitor_id, occurred_at)
  WHERE event_type = 'web_vital';
