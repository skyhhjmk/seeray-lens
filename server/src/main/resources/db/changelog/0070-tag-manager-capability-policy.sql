ALTER TABLE tag_container_security_policy
  ADD COLUMN allowed_tag_types_json JSONB NOT NULL DEFAULT '["page_view","event","custom_html"]'::jsonb,
  ADD COLUMN allow_custom_js_triggers BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE tag_container_security_policy
  ADD CONSTRAINT tag_container_security_policy_allowed_tag_types_array
  CHECK (jsonb_typeof(allowed_tag_types_json) = 'array');
