CREATE TABLE tag_container_environment_release (
  id UUID PRIMARY KEY,
  container_id UUID NOT NULL REFERENCES tag_container(id) ON DELETE CASCADE,
  environment VARCHAR(16) NOT NULL CHECK (environment IN ('development', 'staging', 'production')),
  version INTEGER NOT NULL,
  released_at TIMESTAMPTZ NOT NULL,
  UNIQUE (container_id, environment),
  CONSTRAINT tag_container_environment_release_version_fk
    FOREIGN KEY (container_id, version)
    REFERENCES tag_container_version(container_id, version)
);

INSERT INTO tag_container_environment_release(id, container_id, environment, version, released_at)
SELECT gen_random_uuid(), container.id, 'production', container.published_version, now()
FROM tag_container container
WHERE container.published_version IS NOT NULL
ON CONFLICT (container_id, environment) DO NOTHING;
