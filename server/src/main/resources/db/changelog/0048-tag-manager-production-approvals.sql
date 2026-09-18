CREATE TABLE tag_manager_production_request (
  id UUID PRIMARY KEY,
  container_id UUID NOT NULL REFERENCES tag_container(id) ON DELETE CASCADE,
  base_version INTEGER,
  target_version INTEGER NOT NULL,
  requested_by UUID NOT NULL REFERENCES app_user(id),
  requested_at TIMESTAMPTZ NOT NULL,
  request_note VARCHAR(1000) NOT NULL,
  status VARCHAR(16) NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  reviewed_by UUID REFERENCES app_user(id),
  reviewed_at TIMESTAMPTZ,
  review_note VARCHAR(1000),
  CONSTRAINT tag_manager_production_target_fk
    FOREIGN KEY (container_id, target_version)
    REFERENCES tag_container_version(container_id, version),
  CONSTRAINT tag_manager_production_base_fk
    FOREIGN KEY (container_id, base_version)
    REFERENCES tag_container_version(container_id, version),
  CONSTRAINT tag_manager_production_review_consistency CHECK (
    (status = 'pending' AND reviewed_by IS NULL AND reviewed_at IS NULL)
    OR (status <> 'pending' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX tag_manager_one_pending_production_request_idx
  ON tag_manager_production_request(container_id)
  WHERE status = 'pending';

CREATE INDEX tag_manager_production_request_history_idx
  ON tag_manager_production_request(container_id, requested_at DESC);
