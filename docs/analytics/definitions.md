# SeeRay Lens Analytics Definitions

These definitions are the shared contract for fact processing, tests, APIs and UI.

- **Visitor**: a site-scoped anonymous browser identifier. `Unique Visitor` counts identifiers, not unique humans; clearing storage or changing device creates a new visitor.
- **Session**: events for one site and visitor with the same client session signal, split whenever inactivity exceeds 30 minutes or lifetime exceeds 24 hours. Client identifiers never cross sites or visitors.
- **New visitor**: the first valid session observed for a site-scoped visitor. Later sessions are returning sessions.
- **Returning visitor**: any later valid session for that visitor.
- **Page view**: only an event whose type is `page_view`.
- **Bounce**: exactly one page view and no custom event explicitly carrying `interaction: true`. Background/heartbeat events do not qualify.
- **Session duration**: the latest meaningful event timestamp minus session start. A single-page bounce is zero; page duration is separate.
- **Page duration**: the validated explicit tracker `durationMs`; it is never inferred by summing session or page values.
- **Business day**: the event/session timestamp converted to the Site IANA timezone before extracting the calendar date.
- **Clock skew**: `occurred_at` is used only within +/-24 hours of server `received_at`; otherwise the analytics timestamp is `received_at`.
- **Late event**: raw events remain authoritative. Rebuilding a site (or a recent reconciliation window) reorders events by analytics timestamp and recomputes visitor/session/day facts idempotently.

Facts are derived from `raw_event`; Redis or checkpoints are never the sole source of truth.

The Phase 4 builder currently performs a complete site rebuild for correctness; callers may pass a reconciliation range for API compatibility, but the implementation reloads all raw events for the site. Incremental checkpoint consumption and bounded partial replacement remain a follow-up optimization; a rebuild is always safe and idempotent.
