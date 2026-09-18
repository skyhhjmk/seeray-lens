# Site search analytics

Site search is collected only when the site explicitly opts in. Search terms are not inferred from URL query parameters, which can contain unrelated or sensitive data.

## Tracker integration

For a standard HTML form, mark the form and the tracker captures its search field only when the form is submitted:

```html
<form action="/search" method="get"
      data-seeray-search
      data-seeray-search-category="catalog">
  <input type="search" name="q">
  <button type="submit">Search</button>
</form>
```

The tracker checks the explicit `data-seeray-search-term` marker first, then common search fields (`type="search"`, `name="q"`, `name="query"`, or `name="search"`). It reads only the submitted form field and does not prevent or change form navigation.

For JavaScript/AJAX search, call after the search is completed:

```js
SeeRay.trackSiteSearch(searchInput.value, {
  category: 'catalog',
  resultsCount: results.total
});
```

Choose one method per search action to avoid duplicate events. `resultsCount` is optional; use `0` for a known empty result set and omit it when the count is unknown. Terms are trimmed, whitespace-collapsed, control-character-cleaned, and capped at 256 characters. This explicit field may still contain personal or sensitive information, so sites should avoid sending account numbers, email addresses, names, or other sensitive values. Consent and Do Not Track gates apply to both methods.

## Report

The site Behaviour page includes total searches, search sessions, unique visitors, known no-result searches, no-result rate, average known result count, and the 20 most searched terms. The report uses the shared site date range and optional saved segment. Result-count metrics use only events that supplied a valid non-negative integer; missing or invalid counts are not treated as zero.

`GET /api/v1/sites/{siteId}/analytics/site-search?from=YYYY-MM-DD&to=YYYY-MM-DD&segmentId=...` returns an aggregate summary and up to 100 term/category rows. Search terms are grouped as submitted; page URLs continue to use the normal URL sanitizer and do not preserve arbitrary query parameters.
