# Site audit history

The **Audit log** tab lists successful changes to site-scoped configuration and analytics definitions. It records the actor, action, resource category, resource identifier when available, and timestamp. The list defaults to the most recent 30 days, supports a custom date range, and loads older entries in pages.

The API uses the signed-in workspace member's existing site access check:

```text
GET /api/v1/sites/{siteId}/audit-log?from=YYYY-MM-DD&to=YYYY-MM-DD&limit=25&cursor=...
```

Entries are generated after successful mutations to site settings, allowed domains, saved dashboards, segments, custom dimensions, goals, experiments, funnels, Tag Manager, and heatmap configuration. Analytics queries, tracking ingestion, report previews, failed requests, and request bodies are excluded. The log intentionally does not capture credentials, submitted values, URLs, or other potentially sensitive configuration content. Site deletion removes its audit history; deleting a user leaves the event with no actor account attached.

This is a site-scoped operational history. Workspace membership, token lifecycle, and selected authentication activity are available in the workspace-level views described below; this site view still does not include read-only access. Retention currently follows the lifetime of the site and is not separately configurable.

## Workspace API read access

Workspace activity also has an **API read access** view for owners and admins. It records authenticated human-member `GET` and `HEAD` calls to workspace- or site-scoped APIs, with the actor, optional site, JAX-RS route template, response status, and timestamp. Route templates contain placeholders such as `{siteId}` rather than concrete path IDs. Audit/history endpoints are excluded to avoid logging the act of reading the audit itself. API-token requests are shown separately in Workspace API tokens.

```text
GET /api/v1/workspaces/{workspaceId}/api-read-log?from=YYYY-MM-DD&to=YYYY-MM-DD&limit=25&cursor=...
```

The read history is retained for 30 days and cleaned daily. It does not retain query strings, request or response bodies, credentials, IP addresses, or user-agent values. Authentication failures are not attributable to a verified actor and are not included. This is route-level access metadata, not a record of which individual rows or visitor profiles were returned.

## Workspace authentication activity

Workspace owners and admins can select **Authentication** on the Workspace activity page. It shows successful and rejected sign-ins, session refreshes, sign-outs, and rejected refresh attempts for member accounts known to the system at event time. Unknown email addresses are not logged. Events are attached to each workspace the member belonged to when the event occurred, so a later removal does not erase the history.

```text
GET /api/v1/workspaces/{workspaceId}/auth-activity?from=YYYY-MM-DD&to=YYYY-MM-DD&limit=25&cursor=...
```

Only the event type, member identity, and timestamp are retained for 30 days. Passwords, refresh/access tokens, submitted email values, IP addresses, and user agents are not stored. Audit persistence is best-effort and does not change the authentication response if the audit store is unavailable.
