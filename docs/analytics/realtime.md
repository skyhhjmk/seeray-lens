# Live visitor report

The authenticated `GET /api/v1/sites/{siteId}/analytics/realtime` endpoint returns recent active visits directly from `raw_event`, before the five-minute aggregate refresh. It accepts `windowMinutes` (1–60, default 30) and `limit` (1–100, default 100). A visit is active when the server received an event for that site-scoped visitor/session pair within the selected window. Response rows include the visit's retained page/event counts, entry and latest page, normalized browser/device/location context, and up to 20 most recent actions.

The site Live tab polls every 10 seconds, offers 5-, 15-, and 30-minute windows, and expands each visit into its recent action trail. It does not apply a saved segment or the dashboard date picker: live membership uses raw receive time, while saved-segment evaluation depends on the session fact pipeline. Visitors are anonymous site-local identifiers; the UI only shows a short prefix and the service never queries IP addresses.

The event consumer flushes accepted messages on a one-second schedule, so visibility is near-real-time rather than a delivery-time guarantee. The list is capped at the latest 100 active visits, and action history is limited to the most recent 20 persisted events per visit. Tracker installation and a healthy broker/database pipeline are required for activity to appear.
