# Cohort retention

The site-level **Cohorts** report groups anonymous visitors by the local calendar week of their first meaningful session. A meaningful session has at least one page view or one non-heartbeat event. A visitor is counted as retained in a later week when a meaningful session starts in that week.

The report API is:

```text
GET /api/v1/sites/{siteId}/analytics/cohorts?from=YYYY-MM-DD&to=YYYY-MM-DD&weeks=8&segmentId={optional}
```

`weeks` accepts 4, 8, or 12. Each response row contains the cohort Monday, week index, original cohort size, retained visitor count, retention rate, and whether the seven-day observation period is complete. Week 0 is the first-visit week. The `complete` flag is always true for week 0; later periods are complete only when all seven local calendar days end on or before the selected report end date. The Admin matrix displays incomplete periods as a dash instead of treating partial data as poor retention.

The selected date range filters visitors by the local date of their first meaningful session. Return activity is observed through the selected end date, including sessions that cross a report-period boundary. A saved segment, when selected, is evaluated against each visitor's first meaningful session; it filters the cohort membership, not subsequent return activity.

The Admin navigation is **Visitors → Cohorts**. The view offers 4-, 8-, and 12-week windows, uses the site's shared date and segment selectors, and defaults an untouched real-time range to the last 12 weeks so the retention matrix is useful on first open. The report returns aggregate counts only and does not expose visitor identifiers.
