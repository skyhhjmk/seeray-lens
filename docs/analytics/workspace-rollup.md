# Workspace roll-up reporting

Open **Workspace roll-up** from the workspace's Sites screen to compare sites over a shared inclusive date range. Select or clear individual sites; the report refreshes to show summed page views and visits, a site-by-site comparison, daily traffic trend, and acquisition channels. Selecting a site row opens that site's normal dashboard.

`POST /api/v1/workspaces/{workspaceId}/analytics/rollup` accepts `{ "from": "YYYY-MM-DD", "to": "YYYY-MM-DD", "siteIds": ["…"] }`. If `siteIds` is empty or omitted, all sites in the authorized workspace are included. An explicit site outside the workspace returns the same 404 boundary as other cross-workspace access. A report may include at most 500 sites and 366 inclusive calendar days.

The backend aggregates existing daily facts in bounded SQL queries; it does not join or create visitor identities across domains. `siteVisitors` is the sum of unique visitors deduplicated independently within each site for the selected period. Daily visitor counts are deduplicated independently per site and local business date, then summed for that calendar label. Each site's configured time zone is returned with its comparison row; sites in different time zones can have different day boundaries. Bounce rate is weighted by each site's visit count.

This is a reporting roll-up, not a cross-site identity graph or a claim that the summed visitor count represents distinct people across the workspace.
