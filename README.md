# SeeRay Lens

Lightweight, self-hosted, privacy-first web analytics. See [architecture](docs/architecture/overview.md) and [ADRs](docs/adr/).

## Current scope

The control plane implements local authentication, Workspaces, Sites, allowed domains, API tokens, browser collection, RabbitMQ-backed ingestion, daily analytics aggregation, and the Flutter reporting dashboard. The Flutter Web admin uses the real versioned REST endpoints.

Mobile, desktop, and Flutter Web applications can use the explicit, consent-aware [Flutter SDK](docs/analytics/flutter-sdk.md). It shares the public schema-v1 collector with the Web, Android, and iOS clients.

Custom event properties can be registered as named report dimensions and managed from the site analytics UI. See [custom dimensions](docs/analytics/custom-dimensions.md) for the tracker integration and report behavior.

Reusable audience segments can be composed in the site UI and applied across core reports, including custom-dimension values. See [audience segments](docs/analytics/segments.md) for supported rules and current report coverage.

The site analytics UI includes normalized technology and page-behaviour reports, plus country/continent/region/city breakdowns when a trusted edge proxy is configured. Location collection is disabled by default and does not retain IP addresses; see [visitor locations](docs/analytics/locations.md) for the required proxy setup and privacy limits.

The Live tab reads recent accepted events directly, shows active visits with their latest page and action trail, and refreshes automatically. See [live visitor reports](docs/analytics/realtime.md) for the timing and retention semantics.

Analytics dashboards can be saved per user and site, assembled from a visual library of report widgets, reordered, configured, duplicated, and selected as the default view. The editor does not expose raw JSON. Custom reports can combine supported session dimensions, measures, visual filters, and table/bar displays; each data widget exports its displayed rows to CSV, JSON, or a paginated PDF with filter context. Owners and admins can configure weekly/monthly email reports and daily comparative alerts; delivery uses server-side SMTP/webhook settings and clustered PostgreSQL-backed Quartz scheduling. A site audit log records successful configuration changes without storing request bodies or credentials. Event/custom-dimension joins and user-defined formulas remain out of scope. See [saved dashboards](docs/analytics/dashboards.md), [scheduled reports](docs/analytics/scheduled-reports.md), [analytics alerts](docs/analytics/alerts.md), and [site audit history](docs/analytics/audit-log.md) for details.

Heatmaps are disabled by default. Once an administrator enables them for a site, the tracker can collect sampled click locations, mouse movement samples, and scroll-depth reach for page instances. Heatmap raw batches, facts, and aggregates are isolated from ordinary analytics, so enabling or disabling heatmaps does not change PV, visitor, session, event, or bounce-rate meanings.

## Heatmap integration

Use the normal tracker snippet. The tracker fetches the site's public capture configuration on each page view and only loads the larger recorder module when automatic snapshots or session recordings are enabled:

```html
<script src="https://analytics.example/tracker.js"
        data-site-id="srl_your_public_tracking_id"></script>
```

For same-address PJAX or query-driven replacements, stop the old lifecycle before replacing content, then declare the new layout only after replacement and scroll restoration have completed:

```html
<script>
  SeeRay.beginNavigation();
  // Replace content and restore the target scroll position.
  SeeRay.pageReady({ layoutVersion: 'catalog-v2' });
</script>
```

## Consent and opt-out

For sites that require consent before analytics, add `data-require-consent="true"` to the tracker script and load the supplied banner immediately after it:

```html
<script src="https://analytics.example/tracker.js" data-site-id="srl_your_public_tracking_id" data-require-consent="true"></script>
<script src="https://analytics.example/consent.js" data-site-id="srl_your_public_tracking_id" data-language="en"></script>
```

The banner stores an explicit accept/decline choice in site-scoped local storage. A privacy/settings page can revoke consent with `SeeRay.optOut()` and ask again later with `SeeRay.setConsent(true)`.

## Experiment exposure

Use the site-linked experiment definition from the admin panel. The tracker loads enabled variants from the control plane, keeps allocation stable for the site visitor, and emits an `experiment_exposure` event:

```js
// Add data-experiments="true" to the tracker script.
SeeRay.ready().then(() => {
  const hero = SeeRay.assignExperiment('homepage_hero');
  if (hero === 'new_copy') showNewHero();
});
```

The A/B panel generates this linked snippet from the current definition, so changing variants or disabling an experiment does not require maintaining a second variant list in page code.

Register a named independent scroll container when it should have its own coordinates and depth reach:

```js
const unregister = SeeRay.registerScrollContainer({
  id: 'product-results',
  element: document.querySelector('#product-results')
});
// Call unregister() when the element is removed.
```

Coordinates are CSS pixels grouped by URL, `layoutVersion`, target, viewport, and content dimensions. A same-size redesign that moves content must use a new `layoutVersion`; the service cannot infer that geometry change from coordinates alone. Fixed/sticky and `data-seeray-heatmap-ignore` regions are excluded.

When automatic snapshots are enabled, the lazily loaded recorder uploads an rrweb DOM snapshot from a sampled visitor's real browser. Session recordings are independently disabled by default and have their own sample rate and retention. Input values are masked before upload, canvas capture and font collection are disabled, scripts are removed from snapshots, and replays are rebuilt in rrweb's sandboxed iframe. Mark additional sensitive regions with `data-seeray-mask`; exclude an entire subtree with `data-seeray-ignore`. Do not enable either feature until the site's applicable consent and privacy requirements are met.

For an asynchronous page that has not reached its final layout when capture starts, trigger a fresh snapshot after rendering stabilizes:

```js
SeeRay.captureHeatmapSnapshot();
```

Manual PNG/JPEG snapshots are stored under `/var/lib/seeray-lens/heatmaps` by default and remain available as a fallback. DOM snapshots and recording chunks are stored in PostgreSQL and removed according to their configured retention periods. Set `SEERAY_HEATMAPS_STORAGE_DIR` to a durable mounted directory in production for image snapshots.

For local Flutter Web development, use the backend's configured development origin:

```sh
(cd admin && fvm flutter run -d chrome --web-port 3000)
```

Quarkus Dev Mode has safe local defaults for the encryption key and trusted
proxy list, so it can start without copying production secrets into a laptop.
Production still requires a stable `SEERAY_SECRET_ENCRYPTION_KEY`; enable geo
location only after setting `SEERAY_GEO_TRUSTED_PROXY_CIDRS` to the exact edge
proxy CIDRs.

Native admin builds render DOM snapshots and recordings inside an application WebView. Desktop builds bundle a pinned CEF/Chromium runtime to avoid host WebKit and GPU-driver differences; Android and iOS use their system WebViews. The first desktop build downloads the CEF distribution and is substantially larger than the Web build.

With the Quarkus control plane and PostgreSQL running, the real Flutter REST
loop can be exercised with:

```sh
(cd admin && fvm flutter test test/real_control_plane_integration_test.dart \
  --dart-define=SEERAY_RUN_REAL_API_TESTS=true)
```

The admin keeps its access and refresh credentials in memory for this release, so a browser reload requires login. See [ADR 0007](docs/adr/0007-admin-token-storage-and-refresh.md) for the security rationale.

## Local validation

```sh
./gradlew check
(cd admin && fvm flutter pub get && fvm flutter analyze && fvm flutter test)
(cd tracker && npm ci && npm run lint && npm test && npm run build)
podman compose -f deploy/compose/docker-compose.yml config --quiet
```

Start development dependencies with `podman compose -f deploy/compose/docker-compose.yml up -d`. RabbitMQ Management is available at `http://localhost:15672` for development only.
