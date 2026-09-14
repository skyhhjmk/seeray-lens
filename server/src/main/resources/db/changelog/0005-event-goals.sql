CREATE TABLE analytics_goal_daily (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  goal_name VARCHAR(256) NOT NULL,
  goal_count BIGINT NOT NULL CHECK (goal_count >= 0),
  PRIMARY KEY (site_id, business_date, goal_name)
);
