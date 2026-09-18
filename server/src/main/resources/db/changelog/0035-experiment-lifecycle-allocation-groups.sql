ALTER TABLE experiment_definition
  ADD COLUMN lifecycle_status VARCHAR(16) NOT NULL DEFAULT 'running',
  ADD COLUMN allocation_group VARCHAR(64);

UPDATE experiment_definition
SET lifecycle_status = CASE WHEN enabled THEN 'running' ELSE 'paused' END;

ALTER TABLE experiment_definition
  ADD CONSTRAINT experiment_definition_lifecycle_status_check
    CHECK (lifecycle_status IN ('draft', 'running', 'paused', 'completed', 'archived')),
  ADD CONSTRAINT experiment_definition_allocation_group_check
    CHECK (allocation_group IS NULL OR allocation_group ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  ADD CONSTRAINT experiment_definition_enabled_status_check
    CHECK (enabled = (lifecycle_status = 'running'));

CREATE INDEX experiment_definition_allocation_group_idx
  ON experiment_definition(site_id, allocation_group, lifecycle_status);
