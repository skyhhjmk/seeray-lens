# Heatmap acceptance record

## Verified in the repository

- Server compilation, formatting, and JUnit suite: `./gradlew check`.
- Flutter analysis and widget suite: `fvm flutter analyze && fvm flutter test` in `admin/`.
- Tracker unit suite, lint, and distributable build: `npm test && npm run lint && npm run build` in `tracker/`.
- Compose configuration parses with the supplied RabbitMQ heatmap queue definitions.
- The Tracker lifecycle regression covers repeated `pageReady`, same-URL explicit navigation, and the global lifecycle facade.

## Verified in Chromium with the published tracker asset

Run `npm run test:e2e` in `tracker/` (or `npm run test:e2e:heatmap` for the coordinate case alone). The Playwright fixture serves the checked-in tracker asset from a separate analytics origin and accepts requests with a test collector; it does not run Quarkus, PostgreSQL, or RabbitMQ.

- Hosted privacy preferences work cross-origin: consent is initially unknown, accepting persists identity and permits a collection request, and withdrawal clears identity and stops further collection after reload.
- A fixed-layout page records known clicks before and after document scrolling. The uploaded heatmap events keep the expected document coordinates, viewport/content dimensions, clean page URL, and one stable page-instance ID.

## Not yet browser-accepted

The following still require the live application, configured site domain, RabbitMQ, PostgreSQL, and (where relevant) a fixed-layout fixture page. They have not been represented as passed by the isolated Chromium fixture above:

- Comparing the server-aggregated CSS grid and the Admin heatmap overlay against the uploaded snapshot.
- Smooth and jump scrolling, short documents, and partially visible registered containers.
- Repeated PJAX, same-path back navigation, BFCache restoration, and viewport/content-size changes.
- Touch-only interaction, offline/retry, rate limiting, and duplicate broker delivery.
- Screenshot 1x/2x visual alignment, long-image tiling, zoom/pan overlay alignment, and role behavior in a browser.
- The stated 1,000,000-point / 10,000-instance performance run and its P95 measurement.

These are release gates rather than claims established by source inspection or unit tests.
