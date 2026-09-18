CREATE TABLE analytics_dashboard_definition (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  name VARCHAR(80) NOT NULL,
  widgets JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(site_id, user_id, name)
);

CREATE UNIQUE INDEX analytics_dashboard_one_default_idx
  ON analytics_dashboard_definition(site_id, user_id) WHERE is_default;

CREATE INDEX analytics_dashboard_user_site_idx
  ON analytics_dashboard_definition(user_id, site_id, is_default, updated_at DESC);
