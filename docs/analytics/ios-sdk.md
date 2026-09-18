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
- It does not collect advertising IDs, device models, contacts, location, screen hierarchy, navigation, crashes, or purchases. The server receives the network request and applies its normal site policy. Do not put personal data in screen names, paths, event properties, or goal names.
- The host app owns the privacy UI and must call `setConsent` only from the visitor’s actual choice. Review the site notice and applicable policy before enabling collection.

The package has Linux SwiftPM unit coverage for payload shape, consent, withdrawal, URL minimization, retries, and session rotation. That is not an iOS Simulator or physical-device acceptance; those checks remain required before production rollout.
