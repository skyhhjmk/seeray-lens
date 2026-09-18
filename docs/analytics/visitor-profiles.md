# Anonymous visitor profiles

The Visitors report lists recent site-scoped visits for the selected date range and saved segment. Search by the anonymous visitor ID or entry/exit path, then open a profile to inspect that visitor's matching visits and page/event timeline. The profile also shows lifetime first/last-seen timestamps and visit count independently from the selected report range.

The APIs are:

```text
GET /api/v1/sites/{siteId}/analytics/visitor-log?from=YYYY-MM-DD&to=YYYY-MM-DD&limit=100&segmentId={optional}
GET /api/v1/sites/{siteId}/analytics/visitors/{visitorId}?from=YYYY-MM-DD&to=YYYY-MM-DD&segmentId={optional}
```

Visitor IDs are scoped to the authorized site. A profile returns period totals, up to the latest 50 matching sessions, and up to the latest 100 actions; `hasMoreSessions` and `hasMoreActions` indicate when those detail lists are capped. Narrow the selected date range to inspect older activity. The date range selects sessions by their start date in the site's timezone; actions include the complete accepted journey inside each matching session, even when it crosses the selected period boundary. Lifetime first/last-seen timestamps and lifetime session count are not filtered by the selected period or saved segment; period totals, session history, and actions are.

For privacy, profile actions expose only the event type, minimized page path/title, timestamp, and opaque session ID. They do not expose raw IP addresses, arbitrary event properties, or cross-site visitor identifiers. Location fields are the trusted-proxy-derived facts stored on session records.
