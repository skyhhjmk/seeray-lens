# Technology reports

The tracker attaches normalized browser, browser major version, operating system, operating-system version, device category, language, screen size, viewport size, and display scale to each event. It does not transmit or store the raw browser user-agent string. The collector validates the categorical values and bounds all text/numeric fields before placing the allow-listed context in `raw_event.event_data.context`.

The authenticated `GET /api/v1/sites/{siteId}/analytics/technology` endpoint reports sessions and distinct visitors for each technology value. Dimensions are attributed to the first page-view event in a visit, matching the visitor technology convention used by analytics products. The endpoint accepts `from`, `to`, and optional `segmentId`; the report page shares the site-wide date-range and saved-segment selectors.

Older events without context appear under `Unknown`. Browser privacy settings and browser anti-fingerprinting can also reduce or normalize the collected values. This report is based on normalized client context, not server-side user-agent parsing.
