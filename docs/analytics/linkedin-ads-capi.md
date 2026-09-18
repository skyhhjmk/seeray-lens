# LinkedIn Ads Conversions API

The Acquisition → Offline conversion attribution panel can send explicitly consent-confirmed LinkedIn conversion imports to a LinkedIn Conversions API rule. This is a live provider send; it is not a dry run.

## Setup

1. In Campaign Manager, open the LinkedIn Insight Tag settings and enable Enhanced conversion tracking so LinkedIn adds `li_fat_id` to ad landing-page URLs. See [LinkedIn's click ID setup](https://learn.microsoft.com/en-us/linkedin/marketing/conversions/enabling-first-party-cookies?view=li-lms-2026-05).
2. In the LinkedIn Developer Portal, use a member OAuth token with `rw_conversions` and `r_ads` permissions. The member must have an eligible role on the ad account (billing admin, account manager, campaign manager, or creative manager).
3. Create and enable a LinkedIn conversion rule using the Conversions API method and `DYNAMIC` value type. Associate the rule with the relevant campaigns in Campaign Manager; otherwise LinkedIn has no associated campaigns against which to attribute events.
4. Copy the rule URN from Campaign Manager or the conversion-rule API. It has the form `urn:lla:llaPartnerConversion:123456`.
5. In SeeRay, configure the ad account's currency and OAuth token, then map each enabled SeeRay goal to its LinkedIn rule URN. The token is encrypted at rest and never returned to the browser; leaving the replacement-token field blank preserves it.
6. Reselect the same LinkedIn CSV used for the offline import, confirm consent for every row, and review the irreversible-send confirmation.

## Matching and payload

Every row must be an exact match for an already imported conversion for this site and goal, use `linkedin_ads`, fall within LinkedIn's 90-day event-time window, and match a LinkedIn `li_fat_id` click collected in a tracked session on this same site no more than 90 days before the conversion. The access token is sent only in the HTTPS Authorization header. The event includes the mapped conversion URN, millisecond timestamp, configured-currency goal value, a stable site-scoped event ID, and only the `LINKEDIN_FIRST_PARTY_ADS_TRACKING_UUID` user identifier. No email, name, IP address, session ID, or visitor ID is sent.

The API request uses LinkedIn Marketing API version `202609` (latest as of September 2026) and a single `BATCH_CREATE` request containing at most 5,000 events. A successful provider response is reported as accepted. Stable event IDs can help the receiving platform recognize retries, but SeeRay does not maintain a provider delivery ledger or guarantee exactly-once delivery; inspect the success count before retrying an ambiguous network failure. Successful sends are recorded as `SEND_TO_LINKEDIN_ADS` without storing identifiers or payload contents.

LinkedIn's API access and matching depend on its account permissions, conversion-rule configuration, campaign associations, and first-party tracking settings. Provider acceptance and campaign-level attribution still require validation against a real LinkedIn account.
