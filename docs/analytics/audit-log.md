# Site audit history

The **Audit log** tab lists successful changes to site-scoped configuration and analytics definitions. It records the actor, action, resource category, resource identifier when available, and timestamp. The list defaults to the most recent 30 days, supports a custom date range, and loads older entries in pages.

The API uses the signed-in workspace member's existing site access check:

```text
GET /api/v1/sites/{siteId}/audit-log?from=YYYY-MM-DD&to=YYYY-MM-DD&limit=25&cursor=...
```

Entries are generated after successful mutations to site settings, allowed domains, saved dashboards, segments, custom dimensions, goals, experiments, funnels, Tag Manager, and heatmap configuration. Analytics queries, tracking ingestion, report previews, failed requests, and request bodies are excluded. The log intentionally does not capture credentials, submitted values, URLs, or other potentially sensitive configuration content. Site deletion removes its audit history; deleting a user leaves the event with no actor account attached.

This is a site-scoped operational history, not yet a complete workspace security audit: workspace membership, login/session events, token revocation, and read-only access are not included. Retention currently follows the lifetime of the site and is not separately configurable.
