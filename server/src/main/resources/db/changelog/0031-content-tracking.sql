CREATE INDEX idx_raw_event_content_session_time
  ON raw_event(site_id, client_session_id, client_visitor_id, occurred_at)
  WHERE event_type IN ('content_impression','content_interaction');
