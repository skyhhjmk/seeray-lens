# Meta Ads Conversions API

SeeRay Lens can explicitly send selected CRM-imported Meta conversions to a configured Meta dataset/Pixel through Graph API v26.0. This is an operator-driven export; it does not forward all browser events in the background.

## Configure and send

1. In Meta Events Manager, choose the receiving dataset/Pixel and create a Conversions API access token.
2. In **Acquisition → Offline conversion attribution → Send conversions to Meta Ads**, enter the numeric dataset/Pixel ID, currency, and token. The token is encrypted at rest, never returned to the Admin UI, and is preserved if its replacement field is left blank.
3. Map each enabled SeeRay goal to the corresponding Meta standard or custom event name.
4. Reselect the same CSV previously imported into SeeRay and confirm the explicit ad-storage and conversion-measurement consent statement.
5. Review the irreversible-send confirmation. The server rechecks every row against its site/goal import, the retained hashed click key, and a first-party session before contacting Meta.

The exported event uses the goal's fixed value and configured currency. In the send review, choose the Meta-supported action source that best describes where these imported conversions occurred (`website`, `app`, `business_messaging`, `chat`, `email`, `phone_call`, `physical_store`, `system_generated`, or `other`; default `other`). Meta receives `event_name`, the imported conversion timestamp, an opaque stable `event_id`, the selected `action_source`, and `user_data.fbc`. The `fbc` timestamp is derived from the start time of the matching first-party session that recorded the FBCLID; this is the closest timestamp retained by the current privacy-minimised analytics model, not a separate browser cookie timestamp. The raw FBCLID is sent only for the explicit export request and remains hashed in SeeRay storage. Email, phone, visitor ID, session ID, and raw conversion IDs are not sent.

Events older than seven days or more than five minutes in the future are rejected. Each batch is limited to 1,000 events. The stable `event_id` makes retries recognizable by the receiving platform, but SeeRay does not persist a provider-side delivery ledger or promise exactly-once delivery; operators should inspect the success count before retrying an ambiguous network failure. Every successful send is recorded in the site audit log as `SEND_TO_META_ADS` without identifiers or payload contents.

## Scope and verification

This connector covers already-imported offline conversions whose FBCLID matches a tracked site session. It is not a general event forwarder, a Meta account/event manager, a browser Pixel installer, or a replacement for provider-side event diagnostics. Dataset permission, access-token validity, consent/legal basis, event mapping, and attribution eligibility must be checked in Meta. A successful API response confirms provider receipt, not attribution or Ads Manager reporting.

Automated Quarkus integration tests verify encrypted credential storage, owner/admin controls, imported-row matching, tracked-session matching, consent confirmation, mapped event payload, click-time derivation, redaction, and audit metadata. They do not validate a real Meta account or production attribution.
