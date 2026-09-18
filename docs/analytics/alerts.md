# Comparative analytics alerts

Workspace owners and admins can configure up to 20 daily alerts per site from the **Alerts** tab. Each alert monitors unique visitors, sessions, page views, or bounce rate and fires when the completed site-local day's value increases or decreases by at least the configured percentage versus either the previous day or the same weekday last week. Evaluation time and timezone are shown on each alert; evaluation is once per day and duplicate runs for a site-local report date are skipped.

Available notification channels are displayed from server configuration. Email reuses the SMTP settings documented for [scheduled reports](scheduled-reports.md). Slack and Microsoft Teams webhook URLs are configured only in the server secret store and are never accepted from or returned to the browser:

```text
SEERAY_ALERT_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
SEERAY_ALERT_TEAMS_WEBHOOK_URL=https://...webhook.office.com/...
```

Webhook delivery is HTTPS-only, redirects are disabled, and destination hosts are restricted to the supported Slack and Teams webhook domains. Alerts can select multiple channels; email recipients are managed as a list with a maximum of ten addresses. Failed evaluations/deliveries show a safe generic status in the UI and can be retried on the next daily evaluation. The site audit log records alert create/update/delete metadata, never recipient lists or webhook URLs.

## API

```text
GET    /api/v1/sites/{siteId}/analytics-alerts
POST   /api/v1/sites/{siteId}/analytics-alerts
PUT    /api/v1/sites/{siteId}/analytics-alerts/{alertId}
DELETE /api/v1/sites/{siteId}/analytics-alerts/{alertId}
```

Site members can view alerts. Creation, editing, pause/resume, and deletion require owner/admin role. The API uses typed metric, direction, comparison baseline, percentage threshold, local time, channel list, email recipients, and enabled state; schedules are not free-form cron expressions.
