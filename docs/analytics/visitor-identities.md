# Cross-device visitor profiles

The tracker accepts an optional application-provided User ID for sites that need an authenticated visitor timeline. It is not required for ordinary analytics. Use a stable, opaque, site-specific random identifier that cannot be interpreted outside your application. Never send an email address, phone number, username, real name, or an easily guessed database key: a one-way hash is pseudonymous, not anonymous, and low-entropy identifiers may be guessed.

Set the value only after your application has confirmed both the signed-in account and the required analytics consent. Clear it before recording a logout or account switch:

```js
// After login and consent have both been confirmed:
SeeRay.setUserId(user.analyticsId, 'YOUR_TRACKING_ID');

// On logout, account switch, or consent withdrawal:
SeeRay.setUserId(null, 'YOUR_TRACKING_ID');
```

The tracker does not send the User ID while collection is disallowed, omits it from explicitly anonymous events, and clears its in-memory value on opt-out. The collector immediately derives a deterministic SHA-256 key scoped to the site; the original value is not written to the event message, raw-event row, session fact, or visitor API. The derived key remains pseudonymous data and can still correlate that site's events, so include this purpose in the site's notice and retention policy.

Visitor profiles link browser-scoped visitor IDs only when the retained history for that browser points to exactly one User ID. Lifetime totals and the selected-period visit/action timeline then include sessions with that same site-scoped key. If the browser has used multiple User IDs, or one session contains conflicting IDs, its profile is marked ambiguous and remains separate; no account's sessions are merged through that browser. The profile interface never displays the supplied value or its hash.

The same conservative identity key now drives unique-visitor counts in overview and daily reports, saved-segment previews and reports, custom reports/dimensions, attribution, cohorts, and live-visitor totals. Explicit sessions carrying one User ID are joined across browsers. An anonymous session can inherit a browser's sole User ID only while that browser has no conflicting session; browsers with multiple IDs and sessions that switch IDs remain browser-scoped for their anonymous/conflicting activity. Live visit rows are still sessions, and the API exposes only whether a row represents that identity in the count, never the identity key or hash. User IDs also cannot reconstruct sessions collected before the site began sending them.
