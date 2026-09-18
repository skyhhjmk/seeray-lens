# Goals and conversion comparisons

Create and manage goals from the site's **Goals** report. A goal can match an event type (optionally a particular event name) or a page-view path using exact or contains matching. Each matching event contributes one conversion; the report also shows distinct visits containing the goal, the configured fixed value, and conversion rate among visits matching the selected site range and audience segment.

## Compare conversions

The comparison panel supports two modes:

- **Previous period** compares the selected date range with the immediately preceding range of equal length. The site-wide saved-segment filter applies to both periods. For example, a seven-day range is compared with the seven calendar days directly before it.
- **Compare audiences** compares two distinct saved segments over the same selected dates. The two local audience selectors replace the site-wide segment filter for this comparison. Choose **All visitors** for one side when the useful question is a segment versus the full audience. If no saved segment exists, the panel links to segment management.

Each goal shows conversion events, visits with at least one conversion, conversion rate, and configured goal value on both sides. The delta row reports the conversion-count difference and relative change, conversion-rate difference in percentage points, and fixed-value difference. Relative change is shown as unavailable when the comparison baseline is zero. Goal values are user-configured comparison units, not currency unless the site uses a consistent currency convention.

The comparison reuses the site's authorized analytics range and segment-filtered goal query. Goal definitions are managed separately in the same page; only enabled goals with matching conversions appear in historical report results. This feature does not add e-commerce order or revenue tracking.
