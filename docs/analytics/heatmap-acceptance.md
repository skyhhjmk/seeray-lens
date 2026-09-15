# Heatmap acceptance record

## Verified in the repository

- Server compilation, formatting, and JUnit suite: `./gradlew check`.
- Flutter analysis and widget suite: `flutter analyze && flutter test` in `admin/`.
- Tracker unit suite, lint, and distributable build: `npm test && npm run lint && npm run build` in `tracker/`.
- Compose configuration parses with the supplied RabbitMQ heatmap queue definitions.
- The Tracker lifecycle regression covers repeated `pageReady`, same-URL explicit navigation, and the global lifecycle facade.

## Not yet browser-accepted

The following require a live application, configured site domain, RabbitMQ, PostgreSQL, and a fixed-layout fixture page. They have not been represented as passed by the checks above:

- Clicking known positions before and after document scrolling and comparing the final CSS grid against the uploaded snapshot.
- Smooth and jump scrolling, short documents, and partially visible registered containers.
- Repeated PJAX, same-path back navigation, BFCache restoration, and viewport/content-size changes.
- Touch-only interaction, offline/retry, rate limiting, and duplicate broker delivery.
- Screenshot 1x/2x visual alignment, long-image tiling, zoom/pan overlay alignment, and role behavior in a browser.
- The stated 1,000,000-point / 10,000-instance performance run and its P95 measurement.

These are release gates rather than claims established by source inspection or unit tests.
