# Visit-time report

The **Visit time** report groups session starts into a Monday-first weekday and a 24-hour clock using the site's configured timezone. Each session is counted exactly once, in the local hour when it began; visits crossing midnight are not reassigned based on their later activity.

The report defaults to the last 30 days and follows the shared site date range and saved-segment selector. Its 7-by-24 heatmap shows visit counts by cell, highlights the busiest hour, and exposes the exact value in each cell's tooltip and accessible label. A visit with a matching segment is counted only when the session itself matches.

`GET /api/v1/sites/{siteId}/analytics/visit-time?from=YYYY-MM-DD&to=YYYY-MM-DD&segmentId=...` returns non-empty cells with `dayOfWeek` (Monday `0` through Sunday `6`), `hour` (`0` through `23`), and `sessions`. Older date ranges remain subject to the site's session-fact retention policy.
