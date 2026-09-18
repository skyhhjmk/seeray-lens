CREATE TABLE analytics_annotation (
  id UUID PRIMARY KEY,
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  annotation_date DATE NOT NULL,
  note VARCHAR(500) NOT NULL CHECK (length(btrim(note)) BETWEEN 1 AND 500),
  actor_user_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX analytics_annotation_site_date_idx
  ON analytics_annotation(site_id, annotation_date DESC, id DESC);
