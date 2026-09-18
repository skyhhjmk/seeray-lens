# Visitor engagement report

The **Engagement** report implements the Matomo-style visit-frequency and visitor-interest view using retained session facts. The selected date range and saved segment apply to every count and distribution. Date bounds follow the site's configured timezone and session-fact retention.

Visit frequency is calculated only over matching sessions in the selected range. A visitor with older history can therefore appear in the `1` band when exactly one session matches the current range. This is intentionally different from the lifetime visit total shown on an anonymous visitor profile. The report summarizes matching visitors and sessions, page views per session, tracked events per session, and elapsed session duration.

The distribution bands are:

- Visits per visitor: `1`, `2`, `3`, `4–5`, `6–10`, `11+`.
- Page views per session: `0`, `1`, `2`, `3–5`, `6–10`, `11+`.
- Tracker records per session: `0`, `1–2`, `3–5`, `6–10`, `11+`. This fact count includes page views and heartbeat signals, but excludes Web Vitals samples.
- Session duration: `<10s`, `10–<30s`, `30–<60s`, `1–<3m`, `3–<10m`, `10m+`.

The page defaults to the last 30 days when the site-wide range is still in realtime mode; otherwise it follows the shared site date range and segment selector.

`GET /api/v1/sites/{siteId}/analytics/visitor-interest?from=YYYY-MM-DD&to=YYYY-MM-DD&segmentId=...` returns summary totals and four distribution arrays (`frequency`, `pageViewsPerSession`, `eventsPerSession`, and `durationPerSession`). Each frequency cell contains a visit band, visitor count and session count; each activity cell contains a band and session count. Automated API/UI tests cover date/segment propagation and the selected-period semantics. Real-browser acceptance remains an evidence gate.
