# SeeRay Lens

Lightweight, self-hosted, privacy-first web analytics. See [architecture](docs/architecture/overview.md) and [ADRs](docs/adr/).

## Current scope

The control plane implements local authentication, Workspaces, Sites, allowed domains, API tokens, browser collection, RabbitMQ-backed ingestion, daily analytics aggregation, and the Flutter reporting dashboard. The Flutter Web admin uses the real versioned REST endpoints.

Heatmaps are disabled by default. Once an administrator enables them for a site, the tracker can collect sampled click locations, mouse movement samples, and scroll-depth reach for page instances. Heatmap raw batches, facts, and aggregates are isolated from ordinary analytics, so enabling or disabling heatmaps does not change PV, visitor, session, event, or bounce-rate meanings.

## Heatmap integration

Use the normal tracker snippet, adding `data-heatmap` only after enabling heatmaps in the site’s Behaviour → Heatmaps page:

```html
<script src="https://analytics.example/tracker.js"
        data-site-id="srl_your_public_tracking_id"
        data-heatmap></script>
```

For same-address PJAX or query-driven replacements, stop the old lifecycle before replacing content, then declare the new layout only after replacement and scroll restoration have completed:

```html
<script>
  SeeRay.beginNavigation();
  // Replace content and restore the target scroll position.
  SeeRay.pageReady({ layoutVersion: 'catalog-v2' });
</script>
```

Register a named independent scroll container when it should have its own coordinates and depth reach:

```js
const unregister = SeeRay.registerScrollContainer({
  id: 'product-results',
  element: document.querySelector('#product-results')
});
// Call unregister() when the element is removed.
```

Coordinates are CSS pixels grouped by URL, `layoutVersion`, target, viewport, and content dimensions. A same-size redesign that moves content must use a new `layoutVersion`; the service cannot infer that geometry change from coordinates alone. Fixed/sticky and `data-seeray-heatmap-ignore` regions are excluded. The feature never uploads DOM, input values, element text, selectors, visitor IDs, session IDs, or replayable pointer timelines.

Snapshots are stored under `/var/lib/seeray-lens/heatmaps` by default. Set `SEERAY_HEATMAPS_STORAGE_DIR` to a durable mounted directory in production. A multi-instance deployment requires that path to be shared and read/write-capable on every application instance; a local container filesystem is only suitable for a single application instance.

For local Flutter Web development, use the backend's configured development origin:

```sh
(cd admin && flutter run -d chrome --web-port 3000)
```

With the Quarkus control plane and PostgreSQL running, the real Flutter REST
loop can be exercised with:

```sh
(cd admin && flutter test test/real_control_plane_integration_test.dart \
  --dart-define=SEERAY_RUN_REAL_API_TESTS=true)
```

The admin keeps its access and refresh credentials in memory for this release, so a browser reload requires login. See [ADR 0007](docs/adr/0007-admin-token-storage-and-refresh.md) for the security rationale.

## Local validation

```sh
./gradlew check
(cd admin && flutter pub get && flutter analyze && flutter test)
(cd tracker && npm ci && npm run lint && npm test && npm run build)
podman compose -f deploy/compose/docker-compose.yml config --quiet
```

Start development dependencies with `podman compose -f deploy/compose/docker-compose.yml up -d`. RabbitMQ Management is available at `http://localhost:15672` for development only.
