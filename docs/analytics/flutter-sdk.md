# Flutter SDK

The first-party Flutter SDK is in [`sdk/flutter`](../../sdk/flutter). It supports Flutter applications on Android, iOS, Web, Windows, macOS, and Linux, and sends the same schema-version-1 batches as the web and native clients.

## Add the package

Until a tagged package release is published, consume the source through Git. Pin a tag rather than `master` for production builds.

```yaml
dependencies:
  seeray_analytics_flutter:
    git:
      url: https://github.com/skyhhjmk/seeray-lens.git
      path: sdk/flutter
      ref: master
```

The source change must be pushed before another project can resolve it. The package is not published on pub.dev yet.

## Initialize and collect

Create one client for the application process. The collector and every tracked screen URL must use HTTPS and a host enabled for the selected SeeRay site.

```dart
import 'package:seeray_analytics_flutter/seeray_analytics_flutter.dart';

final analytics = await SeeRayAnalytics.create(
  const SeeRayAnalyticsOptions(
    siteId: 'srl_your_tracking_id',
    apiOrigin: 'https://analytics.example.com',
    requireConsent: true,
  ),
);

// Call only after the application has shown its own privacy choice.
await analytics.setConsent(granted: visitorAcceptedAnalytics);

analytics.trackScreen(
  name: 'pricing',
  url: 'https://www.example.com/mobile/pricing',
);
analytics.trackEvent(
  type: 'signup',
  url: 'https://www.example.com/mobile/signup',
  category: 'account',
  action: 'completed',
  properties: {'plan': 'pro'},
);
analytics.trackGoal(
  name: 'signup_completed',
  url: 'https://www.example.com/mobile/complete',
);
```

The SDK does not observe Flutter routes automatically. Call `trackScreen` when a screen is visible, `trackEvent` for meaningful interactions, and `trackGoal` only after a conversion succeeds. Call `flush()` at an appropriate application background boundary; delivery is best effort and pending in-memory events can be lost when the process terminates. Call `close()` when the app process is shutting down.

## Consent and privacy

- If `requireConsent` is enabled, no identifier is created and no event is queued until `setConsent(granted: true)`.
- `optOut()` or `setConsent(granted: false)` immediately clears queued events, tracker-owned visitor/session IDs, and the current user ID. The denial choice remains stored per site.
- Visitor IDs are random and site-scoped. Session IDs rotate after 30 minutes without a successfully sent event. `setUserId` accepts only an opaque application-owned value and must be cleared at logout or account switch; the server hashes it.
- Query strings and fragments are removed before collection. Do not put personal data in URL paths, screen names, goal names, or event properties.
- The client uses bounded in-memory batches (10 events) and retries failed delivery only while the process remains alive. It records platform, language, display dimensions, and pixel ratio, but never advertising IDs, device model, contacts, location, UI hierarchy, route names, or screen content.

For local development only, `allowInsecureLocalhost: true` permits a collector at `http://localhost`, `http://127.0.0.1`, or `http://[::1]`. Production and non-loopback collectors must use HTTPS.

Flutter and native crash diagnostics, automatic route tracking, heatmaps, recordings, tag manager execution, and automatic content/media/form collection are intentionally outside this first release.
