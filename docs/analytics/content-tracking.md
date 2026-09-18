# Content analytics

Content analytics measures explicitly labelled content impressions and interactions. It does not scrape page text, HTML, image alt text, or form values.

## Mark content in HTML

Add the content name to the block to be measured. Piece and target are optional labels; targets are grouped in reports without query strings or fragments. Mark only the controls whose clicks should count as interactions.

```html
<section
  data-seeray-content-name="home hero"
  data-seeray-content-piece="summer-campaign"
  data-seeray-content-target="/summer">
  <a href="/summer" data-seeray-content-action="primary_cta">
    Shop the summer collection
  </a>
</section>
```

An impression is counted once per marked element and page lifecycle when at least 10% becomes visible. The tracker observes only elements with `data-seeray-content-name`. For content inserted after the initial render, call `SeeRay.refreshContentTracking()` after rendering; PJAX navigation already starts a new measurement lifecycle through `SeeRay.pageReady()`.

## Track from application code

Use the API instead of automatic markup when your application owns the impression and interaction lifecycle:

```js
SeeRay.trackContentImpression('home hero', {
  piece: 'summer-campaign',
  target: '/summer'
});

SeeRay.trackContentInteraction('home hero', {
  piece: 'summer-campaign',
  target: '/summer',
  interaction: 'primary_cta'
});
```

Do not use both API calls and marked HTML for the same event. Calls use the normal consent and Do Not Track gates.

## Report

The Behaviour report shows total impressions, interactions, interaction rate, reached visitors, and a ranked content/piece/target table. It uses the shared date range and selected saved segment. The authenticated endpoint is:

`GET /api/v1/sites/{siteId}/analytics/content?from=YYYY-MM-DD&to=YYYY-MM-DD&segmentId=...`

The Integration page contains a copyable example and guidance. If the report is empty, add labels only to the content that is useful to compare and verify those blocks become visible in the selected date range.
