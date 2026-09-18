# Cohort retention

The site-level **Cohorts** report groups anonymous visitors by either the local calendar week of their first meaningful session or their first conversion of a selected enabled goal. A meaningful session has at least one page view or one non-heartbeat event. A visitor is counted as retained in a later week when a meaningful session starts in that week, regardless of which cohort basis was selected.

The report API is:

```text
GET /api/v1/sites/{siteId}/analytics/cohorts?from=YYYY-MM-DD&to=YYYY-MM-DD&weeks=8&basis=first_visit&segmentId={optional}
```

`weeks` accepts 4, 8, or 12. `basis` accepts `first_visit` (the default) or `goal_conversion`; the latter requires a site-scoped enabled `goalId`. The conversion date is the matched event's analytics timestamp after the normal clock-skew correction. Each response row contains the cohort Monday, week index, original cohort size, retained visitor count, retention rate, and whether the seven-day observation period is complete. Week 0 is the full cohort by definition. Later periods are complete only when all seven local calendar days end on or before the selected report end date. The Admin matrix displays incomplete periods as a dash instead of treating partial data as poor retention.

The selected date range filters visitors by the local date of the selected cohort event: the first meaningful session or the first matching goal conversion. Return activity is observed through the selected end date, including sessions that cross a report-period boundary. A saved segment, when selected, is evaluated against each visitor's cohort-defining session (first meaningful session or first goal-conversion session); it filters cohort membership, not subsequent return activity.

The Admin navigation is **Visitors → Cohorts**. The view offers an explanatory cohort-basis selector, a goal selector populated from the site's configured goals (with a shortcut to goal management), 4-, 8-, and 12-week windows, and the shared site date and segment selectors. It defaults an untouched real-time range to the last 12 weeks so the retention matrix is useful on first open. The report returns aggregate counts only and does not expose visitor identifiers.
