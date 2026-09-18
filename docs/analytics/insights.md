# Automatic analytics insights

The Insights report highlights notable changes for page views by page path, acquisition sessions by their full channel/source/medium/campaign/term/content tuple, and tracked event counts other than `page_view` (page views are already reported as their own category). It also summarizes page views, unique visitors, and sessions.

## Comparison and noise controls

- The selected date range is compared with the immediately preceding range of exactly the same inclusive length. Dates follow the site's configured timezone.
- A new item is shown when its current count is at least 20. An item that disappears is shown when its previous count was at least 20.
- For items present in both periods, the absolute difference must be at least 10 and the relative difference must be at least 25% of the previous count.
- Each category is ranked by absolute change and limited to five rows. This keeps the report scannable; it is not a statistical-significance test or a forecast.
- When a segment is selected, both comparison periods and every included dimension use that same segment.

This first version is intended to make obvious, explainable changes easier to notice, not to replace configurable alerts, custom reports, or an anomaly-detection model. Sparse sites may see few or no insights; widen the period or remove a narrow segment to increase the available volume.
