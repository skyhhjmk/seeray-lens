# Scheduled email reports

Workspace owners and admins can create up to 20 scheduled reports per site from the **Email reports** tab. Each report supports one to ten recipients, weekly or monthly delivery, and one or more sections: overview (unique visitors, sessions, page views), top 20 pages, and top 30 acquisition source/medium combinations. Reports are sent as a readable email with a bounded CSV attachment. Recipient addresses are delivered individually so recipients do not see one another.

Schedules save the site's IANA timezone when they are created or edited. Weekly delivery sends the previous seven completed site-local days; monthly delivery sends the previous full calendar month. The monthly day is limited to 1–28 to avoid ambiguous short-month dates. If the site timezone later changes, existing schedules keep their saved timezone; edit and save them to move to the current site timezone. A manual **Send now** uses the same completed-period rule. Missed cron occurrences are skipped rather than sent late; use **Send now** if a delivery needs to be regenerated.

Email delivery is disabled by default. Configure these server-side environment variables; SMTP credentials are never entered or returned by the admin UI:

```text
SEERAY_REPORTS_EMAIL_ENABLED=true
SEERAY_SMTP_HOST=smtp.example.net
SEERAY_SMTP_PORT=587
SEERAY_SMTP_USERNAME=...
SEERAY_SMTP_PASSWORD=...
SEERAY_SMTP_FROM=analytics@example.net
SEERAY_SMTP_STARTTLS=REQUIRED
SEERAY_SMTP_TLS=false
```

Keep credentials in the deployment secret store. Production mock-mail mode is off unless explicitly enabled with `SEERAY_MAILER_MOCK=true`. Changing the server switch to disabled prevents future delivery; enabled schedules remain visible and report a delivery failure until mail is restored.

Schedules and run status are stored in PostgreSQL. Quarkus Quartz uses its clustered JDBC store, so schedules survive restart and only one node claims a due occurrence. Successful and failed delivery time, period, and a safe diagnostic are shown in the management page. The site audit log records schedule changes and manual send actions without storing recipient lists or message contents.

## API

```text
GET    /api/v1/sites/{siteId}/scheduled-reports
POST   /api/v1/sites/{siteId}/scheduled-reports
PUT    /api/v1/sites/{siteId}/scheduled-reports/{reportId}
DELETE /api/v1/sites/{siteId}/scheduled-reports/{reportId}
POST   /api/v1/sites/{siteId}/scheduled-reports/{reportId}/send-now
```

Workspace members can view schedules. Creation, changes, deletion, and manual delivery require owner/admin role. The API accepts typed frequency, weekday/month day, local time, recipient list, section list, and enabled state; it does not accept user-authored cron expressions.
