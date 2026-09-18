# Android SDK

The first-party Android library is in [`sdk/android`](../../sdk/android). It sends the same schema-version-1 event batches as the Web tracker and requires Android API 23 or newer. The Android library adds the Internet permission through manifest merging and enables Java time desugaring for API 23–25.

## Build and install locally

From the repository root, build and test the release artifact:

```sh
./gradlew -p sdk/android test assembleRelease
```

To install the current source into the local Maven repository:

```sh
./gradlew -p sdk/android publishReleasePublicationToMavenLocal
```

Then add `mavenLocal()` to the consuming Android project's repositories and add:

```kotlin
implementation("io.seeray.lens:seeray-analytics-android:0.1.0")
```

This publishes only to the developer's local Maven repository; it is not a public Maven Central release.

## Quick start

```kotlin
val analytics = SeeRayAnalytics(
    context = applicationContext,
    options = SeeRayAnalyticsOptions(
        siteId = "srl_your_tracking_id",
        apiOrigin = "https://analytics.example.com",
        requireConsent = true,
    ),
)

// Present the app's own privacy choice before collecting, and honor the result:
analytics.setConsent(granted = userAcceptedAnalytics)

// Use an HTTPS URL on a host configured in this SeeRay site's allowed domains.
analytics.trackScreen(
    screenName = "pricing",
    url = "https://www.example.com/mobile/pricing",
)
analytics.trackEvent(
    eventType = "signup",
    url = "https://www.example.com/mobile/signup",
    category = "account",
    action = "completed",
    name = "mobile signup",
)

// Only use an opaque, non-personal application identifier, and clear it at logout/account switch.
analytics.setUserId("customer-opaque-id")
analytics.setUserId(null)
```

The client starts a bounded background flush loop. Call `flush()` when an app lifecycle boundary needs an earlier send; it returns a `Future<Boolean>` and must not be waited on the UI thread. `close()` is non-blocking and schedules one final batch on the worker. Delivery is best-effort: pending events are held in memory, batches are retried after a failure while the process is alive, and app termination can lose unsent events.

## Collection and privacy contract

- Collection is active by default unless `requireConsent` is enabled. In required mode, the SDK does not create persistent visitor/session identifiers or queue events before consent is granted. `optOut()` persists denial, clears queued events and removes tracker-owned identifiers.
- The SDK creates a random site-scoped visitor ID and rotates the random session ID after 30 minutes without an event. It does not use advertising IDs, device models, contacts, location, or fingerprinting.
- It records only explicitly supplied page/screen, event, goal, and scalar event-property values. It does not automatically infer screen names, navigation, or purchases. Native crash diagnostics are separately opt-in and disabled by default. Ecommerce collection is intentionally not provided.
- URL query strings and fragments are removed before transmission. The collector also applies its server-side URL minimization. Avoid putting personal data in URL paths, titles, event names, or custom properties; client-side removal cannot recognize application-specific secrets.
- Android version, generic `Android` OS, generic `mobile` device type, and the app language are included as technical context. The host app remains responsible for its consent UX and for using the SDK only where its privacy notice permits.
- `trackEvent` should use the exact event type/name configured by a SeeRay goal when the event is intended to satisfy that goal. `trackGoal` emits the built-in `goal` event for simple goal reporting.

## Native crash diagnostics

Native crash capture is off unless `captureNativeCrashes = true` is explicitly set. When enabled, also provide an immutable `appRelease` and an HTTPS `crashContextUrl` whose host is enabled in this site's allowed-domain list. The last explicitly tracked screen URL is preferred; the configured context URL covers a crash before the app has tracked its first screen.

Native diagnostics always require a separate explicit app choice, even if the site does not require consent for ordinary analytics. If the site requires analytics consent, grant it before calling `setNativeCrashConsent(true)` for the crash-diagnostics choice. Call `setNativeCrashConsent(false)` when that choice is withdrawn. `setConsent(false)` also clears crash consent and pending reports.

The uncaught-exception handler records only the exception class, a bounded server-redacted message, and one top application frame. It does not send a full stack, visitor/session/user IDs, title, referrer, or query string. The redacted event is written synchronously to the app's Android no-backup storage and retried on the next launch; it is deleted after acceptance, consent withdrawal, or when capture is disabled. The SDK chains to the app's previously registered exception handler. The on-device journal is bounded to ten pending reports.

The report includes platform and release so Android issues are distinct from browser JavaScript errors. Source-map symbolication remains JavaScript-only; R8/ProGuard mapping-file upload and retrace are not yet supported. Review error messages before enabling collection because application-specific secrets cannot all be recognized by generic redaction.

The first Android release covers client analytics and opt-in top-frame native crash diagnostics. iOS native crash capture, Android R8/ProGuard symbolication, public Maven distribution, and real-device acceptance remain outstanding; unit tests and an AAR build are not device-level production acceptance.

The site-specific setup wizard is available in Admin → Integration → **Android SDK**. It generates Kotlin configuration and tracking examples from the selected tracking ID, endpoint and consent policy, warns instead of generating unusable setup code when the endpoint is not HTTPS, and explains the current local-Maven-only artifact distribution. The SDK is not yet published to a public Maven repository.
