ALTER TABLE organization
  ADD COLUMN brand_name VARCHAR(120),
  ADD COLUMN brand_accent_color VARCHAR(7),
  ADD COLUMN brand_logo_url VARCHAR(2048);

ALTER TABLE organization
  ADD CONSTRAINT organization_brand_accent_color_format
  CHECK (brand_accent_color IS NULL OR brand_accent_color ~ '^#[0-9A-Fa-f]{6}$');
