CREATE TABLE app_user (
  id UUID PRIMARY KEY,
  email VARCHAR(320) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  display_name VARCHAR(120) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISABLED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE organization (
  id UUID PRIMARY KEY, name VARCHAR(120) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE organization_member (
  organization_id UUID NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role VARCHAR(16) NOT NULL CHECK (role IN ('OWNER', 'ADMIN', 'VIEWER')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, user_id)
);
CREATE TABLE auth_session (
  id UUID PRIMARY KEY, user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  refresh_token_hash CHAR(64) NOT NULL UNIQUE, expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_used_at TIMESTAMPTZ
);
CREATE TABLE site (
  id UUID PRIMARY KEY, organization_id UUID NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL, tracking_id VARCHAR(64) NOT NULL UNIQUE,
  timezone VARCHAR(64) NOT NULL, default_language VARCHAR(35) NOT NULL,
  tracking_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  raw_retention_days INTEGER NOT NULL DEFAULT 30 CHECK (raw_retention_days BETWEEN 1 AND 3650),
  aggregate_retention_days INTEGER NOT NULL DEFAULT 730 CHECK (aggregate_retention_days BETWEEN 1 AND 3650),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (raw_retention_days <= aggregate_retention_days)
);
CREATE INDEX idx_site_organization ON site(organization_id);
CREATE TABLE site_allowed_domain (
  id UUID PRIMARY KEY, site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  host VARCHAR(253) NOT NULL, allow_subdomains BOOLEAN NOT NULL DEFAULT FALSE, enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(site_id, host)
);
CREATE TABLE api_token (
  id UUID PRIMARY KEY, organization_id UUID NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL, token_prefix VARCHAR(20) NOT NULL, token_hash CHAR(64) NOT NULL UNIQUE,
  scopes JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), expires_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ, revoked_at TIMESTAMPTZ
);
