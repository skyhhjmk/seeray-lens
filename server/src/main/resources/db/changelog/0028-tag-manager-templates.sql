CREATE TABLE tag_manager_template (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL,
  description VARCHAR(500),
  tags_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (organization_id, name)
);

CREATE INDEX tag_manager_template_org_idx ON tag_manager_template(organization_id, name);
