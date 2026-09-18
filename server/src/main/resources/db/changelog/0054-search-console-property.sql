CREATE TABLE search_console_property (
  site_id UUID PRIMARY KEY REFERENCES site(id) ON DELETE CASCADE,
  property_url VARCHAR(2048) NOT NULL,
  updated_by UUID REFERENCES app_user(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
