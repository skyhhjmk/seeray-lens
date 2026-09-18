ALTER TABLE scheduled_analytics_report
  ADD COLUMN timezone VARCHAR(80) NOT NULL DEFAULT 'UTC';
ALTER TABLE scheduled_analytics_report ALTER COLUMN timezone DROP DEFAULT;
