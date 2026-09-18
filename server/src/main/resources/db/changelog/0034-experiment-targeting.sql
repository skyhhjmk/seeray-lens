ALTER TABLE experiment_definition
  ADD COLUMN targeting_json JSONB NOT NULL DEFAULT '{"pathPrefixes":[],"deviceTypes":[]}'::jsonb;

ALTER TABLE experiment_definition
  ADD CONSTRAINT experiment_definition_targeting_object_check
  CHECK (jsonb_typeof(targeting_json) = 'object');
