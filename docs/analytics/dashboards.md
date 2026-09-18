# Saved analytics dashboards

Each workspace member can save up to 20 personal dashboards per site. A dashboard can contain up to 20 report widgets. Layouts are private to the creating user; they are not shared with every workspace member. The initial **Overview** is a built-in starter layout and is not persisted until it is customized and saved.

## Build and manage a dashboard

Open the dashboard selector to switch between saved views, create a blank dashboard, duplicate the current view, set a default, or delete a view. Select **Customize** to edit a layout:

1. Add a report from the visual widget library.
2. Drag cards to arrange them in the order that is useful to you.
3. Open a card's settings to change its title and any supported measure, chart style, technology/location dimension, or row count. A **Custom report** starts with an editor for its breakdown, measure, visualization, audience filters, and filter-combination rule.
4. Rename the dashboard or make it the default view, then save. **Discard** restores the last saved layout.

The editor does not expose the stored JSON representation. Unsaved layout changes are local to the editor until saved.

## Available widgets

- Key metrics: page views, unique visitors, visits, bounce rate, and average visit duration.
- Trend chart: visits, page views, or unique visitors, shown as a line or bar chart.
- Top pages and page titles.
- Traffic channels and new/returning visits.
- Events and goal conversions.
- Technology breakdowns for browser, browser/OS version, operating system, device type, language, screen/viewport size, or display scale.
- Visitor locations by country, continent, region, or city.
- Live visitors, refreshed every ten seconds using the latest 30 minutes of accepted events.
- Custom report: group by event type, registered custom dimensions, or session dimensions such as entry/exit page or title, referrer, campaign fields, visitor type, browser/OS/device, language, and available location fields. Any two distinct supported dimensions can be paired, including event type or registered properties. Measures include visits, unique visitors, page views, events, bounced visits, average duration, bounce rate, and a named calculated metric. Calculated metrics combine two allowlisted measures with addition, subtraction, multiplication, or division, and can be displayed as a number or percentage; division by zero returns 0. Choose a table or bar display and add up to five visual audience conditions; conditions can match all or any.

The site date range and saved segment selectors apply to the historical widgets whose reports support them. Custom-report-local audience conditions combine with the selected saved segment using AND. The live widget uses its rolling 30-minute window and does not apply the historical date range or segment. Location data requires trusted-proxy location collection to be configured.

Each data widget has a report-level export menu for CSV, JSON, and PDF. Exports contain the rows shown by that widget for the selected date range and segment, and custom-report exports also include the chosen filters and visualization metadata. PDF files use a paginated report layout with a repeated table header, report period, filter context, and page numbers. CSV is UTF-8 with a BOM for spreadsheet compatibility and protects cells that could be interpreted as formulas. PDF font assets include an OFL-licensed Simplified Chinese subset; characters outside its glyph set are shown as `?` so unusual names do not break layout. CSV and JSON retain the original text unchanged.

Custom reports use server-approved session dimensions, event-type breakdowns, registered custom dimensions, and measures, plus the existing safe segment-rule vocabulary. Any two distinct supported dimensions can be paired. When a pair includes event type or a registered custom property, values are joined from the same raw event; an event without that registered property is grouped under `Unknown`. The event measure counts events in the exact pair, while visit and visitor measures count a visit/visitor once per pair; visits and unique visitors can recur across rows, so row totals are not additive. Standalone custom-dimension reports group visit-level measures once per distinct value seen during a visit, and calculated-metric event operands count only events carrying that value. Registered custom dimensions follow the separate value semantics documented in [custom dimensions](custom-dimensions.md). Nested arbitrary property paths, three-or-more-dimension pivots, and browser acceptance are not yet supported. Scheduled weekly/monthly email reports cover the overview, top pages, and acquisition sources; comparative alerts are managed from the Alerts tab. See [scheduled email reports](scheduled-reports.md) for timing, permissions, SMTP setup, and API details, and [analytics alerts](alerts.md) for comparative thresholds and delivery setup.

## API

The authenticated site endpoints are:

```text
GET    /api/v1/sites/{siteId}/dashboards
POST   /api/v1/sites/{siteId}/dashboards
PUT    /api/v1/sites/{siteId}/dashboards/{dashboardId}
POST   /api/v1/sites/{siteId}/dashboards/{dashboardId}/duplicate
DELETE /api/v1/sites/{siteId}/dashboards/{dashboardId}
POST   /api/v1/sites/{siteId}/analytics/custom-report/query?from=YYYY-MM-DD&to=YYYY-MM-DD
```

Custom-report queries accept typed dimension/metric/filter fields in the request body. For `metric: "formula"`, the `formula` object contains `name`, `leftMetric`, `operator`, `rightMetric`, and `format`; measure names, operations, and formats are allowlisted, and user input is never treated as SQL. The API validates widget types and type-specific options, layout limits, titles, and unique widget IDs. Workspace members may view their own layouts; each user's saved dashboards are isolated from other members.
