# Custom dimensions

Custom dimensions turn a useful scalar event property into a named, site-scoped report. A workspace owner or administrator can create up to 20 dimensions per site from the Dimensions tab. Each definition has a display name, an immutable property key, a description, and a report availability switch.

## Send values

The tracker accepts event properties through `SeeRay.track` or `SeeRay.push`. Use the exact property key shown in the dimension editor:

```js
SeeRay.track('product_interaction', {
  properties: { subscription_plan: 'pro' }
});
```

String, number, and boolean values appear in the value report. Objects, arrays, and null values are ignored for dimension breakdowns. Keep values low-cardinality and avoid personal or sensitive information; the event itself may contain other properties independently of registered dimensions.

The dimension's own report shows event count and distinct site-scoped sessions and visitors for each value. The visual custom-report builder and saved dashboard widgets also offer enabled custom dimensions by their display name; they apply the same saved audience segment and report filters. The **Events** measure counts only events carrying that scalar value. Visit-level measures (visits, visitors, page views, duration and bounce) group each visit under every distinct value observed during that visit; a visit with no scalar value is grouped under “Unknown”. If one visit contains multiple values, its visit-level measure is counted once under each value, so those rows are intentionally not additive. The selected reporting dates use the site's timezone. At most the top 100 values are shown.

## Manage definitions

The editor provides the setup snippet, create/edit/delete actions, and pause/enable controls. Pausing hides the dimension report while retaining its definition; deleting removes the definition and report entry while leaving already collected raw events untouched. Create a new definition if the event property key needs to change.

Management API:

```text
GET    /api/v1/sites/{siteId}/custom-dimensions
POST   /api/v1/sites/{siteId}/custom-dimensions
PUT    /api/v1/sites/{siteId}/custom-dimensions/{dimensionId}
DELETE /api/v1/sites/{siteId}/custom-dimensions/{dimensionId}
GET    /api/v1/sites/{siteId}/custom-dimensions/{dimensionId}/report?from=YYYY-MM-DD&to=YYYY-MM-DD
```
