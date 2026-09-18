# Web Vitals

SeeRay Lens can collect the three Core Web Vitals for real page visits and report their p75 values overall and by page. Collection is opt-in per tracking snippet: open a site's Integration page, choose **Web Vitals**, and copy the generated snippet.

```html
<script src="https://lens.example.com/tracker.js" data-site-id="YOUR_SITE_ID" data-web-vitals></script>
```

This enables LCP (largest contentful paint), INP (interaction to next paint), and CLS (cumulative layout shift). It does not capture DOM, visible text, form values, resource URLs, or attribution/debug data. Collection follows the tracker's Do Not Track and consent settings. Without the `data-web-vitals` attribute, normal page and event tracking is unchanged and no Web Vitals listeners are started.

The report shows the p75 for each metric and a page-by-metric table. Later updates for the same metric ID replace earlier values, so CLS and INP updates do not inflate sample counts. Samples are attributed to the page path and requested date range, and use the report's selected saved segment. Web Vitals are not listed as ordinary tracked events and are excluded from session event counts.

Good / needs-improvement / poor buckets use Google's current Core Web Vitals thresholds, evaluated per measurement:

| Metric | Good | Needs improvement | Poor |
| --- | --- | --- | --- |
| LCP | ≤ 2.5 s | > 2.5 s to 4 s | > 4 s |
| INP | ≤ 200 ms | > 200 ms to 500 ms | > 500 ms |
| CLS | ≤ 0.1 | > 0.1 to 0.25 | > 0.25 |

See [Google's threshold definition](https://web.dev/articles/defining-core-web-vitals-thresholds). p75 is a percentile summary of the samples collected in the selected report range; it is not a Search Console or CrUX ranking signal.

The browser library reports metrics only when the browser exposes the required APIs. Consequently, an empty or sparse report can mean the snippet is not enabled, consent/DNT prevented collection, or the visitors' browsers did not support a given metric. Browser-level acceptance is still required before claiming production coverage.
