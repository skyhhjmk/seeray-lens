CREATE TABLE heatmap_instance_scroll_bin (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  page_instance_id UUID NOT NULL,
  variant_id UUID NOT NULL REFERENCES heatmap_variant(id) ON DELETE CASCADE,
  depth_bin SMALLINT NOT NULL CHECK (depth_bin BETWEEN 0 AND 99),
  PRIMARY KEY (site_id, page_instance_id, variant_id, depth_bin)
);
