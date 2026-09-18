CREATE INDEX idx_raw_event_site_search_session_time
  ON raw_event(site_id, client_session_id, client_visitor_id, occurred_at)
  WHERE event_type='site_search';
