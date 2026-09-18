CREATE INDEX idx_raw_event_site_form_occurred
  ON raw_event(site_id, occurred_at)
  WHERE event_type IN ('form_view','form_start','form_field','form_field_time','form_error','form_submit','form_success','form_failure');
