CREATE TABLE workspace_invitation (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  invited_email VARCHAR(320) NOT NULL,
  role VARCHAR(16) NOT NULL CHECK (role IN ('ADMIN', 'VIEWER')),
  token_hash CHAR(64) NOT NULL UNIQUE,
  invited_by UUID REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  accepted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  CHECK (expires_at > created_at)
);

CREATE INDEX workspace_invitation_org_created_idx
  ON workspace_invitation(organization_id, created_at DESC);
CREATE UNIQUE INDEX workspace_invitation_open_email_idx
  ON workspace_invitation(organization_id, invited_email)
  WHERE accepted_at IS NULL AND revoked_at IS NULL;
