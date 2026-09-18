# iOS SDK

The first-party native client is a Swift Package at the repository root. It supports iOS 15 and later and exposes the `SeeRayAnalytics` product. In Admin, open the selected site’s Integration page and choose **iOS SDK** to get site-specific SwiftPM, initialization, consent, and event examples.

## Add the package

In Xcode choose **File → Add Package Dependencies**, enter:

```text
https://github.com/skyhhjmk/seeray-lens.git
```

Select the `master` branch and the `SeeRayAnalytics` library product. The repository is public; the branch is not a versioned SDK release. Push the SDK changes before consumers can resolve them. Use a tagged release once one is published for reproducible production builds rather than following a moving branch.

## Initialize and collect

```swift
import SeeRayAnalytics

let analytics = try SeeRayAnalytics(
    options: .init(
        siteId: "srl_your_tracking_id",
        apiOrigin: "https://analytics.example.com",
        requireConsent: true
    )
)

// Call only after the application has shown its privacy choice:
await analytics.setConsent(granted: visitorAcceptedAnalytics)

await analytics.trackScreen(
    name: "pricing",
    url: "https://www.example.com/mobile/pricing"
)
await analytics.trackEvent(
    type: "signup",
    url: "https://www.example.com/mobile/signup",
    category: "account",
    action: "completed",
    properties: ["plan": .string("pro")]
)
await analytics.trackGoal(
    name: "signup_completed",
    url: "https://www.example.com/mobile/complete"
)
```

`SeeRayAnalytics` is an actor: call its methods with `await` from the application’s async work. The app explicitly reports visible screens; no navigation or crash hooks are installed automatically. Event properties are scalar `SeeRayValue` values. Call `flush()` when the application has an appropriate background transition; delivery is best effort while the process remains alive.

## Consent and data handling

- If `requireConsent` is true, the initial state is unknown: no event is queued and no persistent visitor/session ID is written until consent is granted.
- Withdrawal is immediate: pending events and SDK-owned visitor/session IDs are cleared. The denial choice remains stored for that site on that device.
- The SDK accepts HTTPS collector origins only. Event URLs must use HTTP or HTTPS; query strings and fragments are stripped before transmission, and the server checks site-domain authorization.
- Visitor IDs are random and site-scoped. Session IDs rotate after 30 minutes without activity. Batches contain at most 10 events, the in-memory queue is bounded at 100, and failed batches are retried while the app process remains alive.
- It does not collect advertising IDs, device models, contacts, location, screen hierarchy, or infer navigation. Native exception reports are separately opt-in; see below. Purchases are not tracked automatically.
- The host app owns the privacy UI and must call `setConsent` only from the visitor’s actual choice. Review the site notice and applicable policy before enabling collection.

The package has Linux SwiftPM unit coverage for payload shape, consent, withdrawal, URL minimization, retries, and session rotation. That is not an iOS Simulator or physical-device acceptance; those checks remain required before production rollout.

## Optional native exception diagnostics

Native diagnostics are disabled unless `captureNativeCrashes` is enabled in the SDK options, and still require an independent explicit choice through `setNativeCrashConsent(true)`. If `requireConsent` is enabled, grant ordinary analytics consent first. Withdrawal of either applicable choice deletes queued crash reports.

```swift
let analytics = try SeeRayAnalytics(
    options: .init(
        siteId: "srl_your_tracking_id",
        apiOrigin: "https://analytics.example.com",
        requireConsent: true,
        captureNativeCrashes: true,
        appRelease: "ios-4.2.1+88",
        crashContextURL: "https://www.example.com/mobile/"
    )
)

// After the visitor accepts analytics and crash diagnostics separately:
await analytics.setConsent(granted: visitorAcceptedAnalytics)
await analytics.setNativeCrashConsent(granted: visitorAcceptedCrashDiagnostics)
```

The SDK currently captures uncaught Objective-C `NSException`s only. It does not capture Swift `fatalError`, POSIX signals such as `SIGABRT`/`SIGSEGV`, watchdog termination, jetsam, or device-level failures. Reports contain a redacted exception name/message and one top symbol, never a full stack or visitor/session/user IDs. They are synchronously written to the app Caches directory, marked excluded from backup, and retried at the next launch while consent remains granted. The URL comes from the last tracked screen or the HTTPS `crashContextURL` fallback; configure it with an enabled site domain.

This hook is process-global and delegates to the exception handler installed before SeeRay. Exception messages and symbol names can still contain application-specific sensitive text that generic redaction cannot recognize. Linux SwiftPM tests verify consent, redaction, outbox recovery, and anonymous delivery; iOS Simulator/device acceptance remains required before production use.
