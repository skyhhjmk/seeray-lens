ALTER TABLE analytics_session ADD COLUMN identity_key VARCHAR(80);

WITH browser_identities AS (
  SELECT site_id, visitor_id, count(DISTINCT user_id_hash) identity_count,
         min(user_id_hash) user_id_hash, coalesce(bool_or(user_id_conflict), false) has_conflict
  FROM analytics_session
  GROUP BY site_id, visitor_id
)
UPDATE analytics_session s
SET identity_key = CASE
  WHEN s.user_id_hash IS NOT NULL THEN 'user:' || s.user_id_hash
  WHEN b.identity_count = 1 AND NOT b.has_conflict THEN 'user:' || b.user_id_hash
  ELSE 'browser:' || v.client_visitor_id
END
FROM browser_identities b
JOIN analytics_visitor v ON v.id = b.visitor_id AND v.site_id = b.site_id
WHERE s.site_id = b.site_id AND s.visitor_id = b.visitor_id;

ALTER TABLE analytics_session ALTER COLUMN identity_key SET NOT NULL;
CREATE INDEX idx_analytics_session_site_identity_started
  ON analytics_session(site_id, identity_key, started_at);

CREATE TABLE visitor_identity_day_fact (
  site_id UUID NOT NULL REFERENCES site(id) ON DELETE CASCADE,
  business_date DATE NOT NULL,
  identity_key VARCHAR(80) NOT NULL,
  visitor_id UUID NOT NULL REFERENCES analytics_visitor(id) ON DELETE CASCADE,
  PRIMARY KEY(site_id, business_date, identity_key, visitor_id)
);
CREATE INDEX idx_visitor_identity_day_fact_key
  ON visitor_identity_day_fact(site_id, identity_key, business_date);

INSERT INTO visitor_identity_day_fact(site_id, business_date, identity_key, visitor_id)
SELECT DISTINCT d.site_id, d.business_date,
       coalesce(s.identity_key, 'browser:' || v.client_visitor_id), d.visitor_id
FROM visitor_day_fact d
JOIN analytics_visitor v ON v.id = d.visitor_id AND v.site_id = d.site_id
LEFT JOIN analytics_session s ON s.site_id = d.site_id AND s.visitor_id = d.visitor_id
  AND d.business_date BETWEEN (s.started_at AT TIME ZONE (SELECT timezone FROM site WHERE id = d.site_id))::date
  AND (s.last_activity_at AT TIME ZONE (SELECT timezone FROM site WHERE id = d.site_id))::date
ON CONFLICT DO NOTHING;
