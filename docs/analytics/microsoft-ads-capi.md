# Microsoft Ads Conversions API

SeeRay Lens can send imported, consent-confirmed Microsoft Ads offline conversions to a UET tag through Microsoft's Conversions API (CAPI). This is an explicit owner/admin workflow; it does not automatically export every conversion or forward identifiers in the background.

## Connect a destination

1. In Microsoft Advertising, select or create a UET tag, enable Conversions API for the tag, and copy its tag-specific token. Microsoft currently documents the direct endpoint as `POST https://capi.uet.microsoft.com/v1/{tagId}/events` with a bearer token.
2. In the site's Offline conversions page, open **Send conversions to Microsoft Ads** and enter the UET tag ID, ISO 4217 currency, and token. SeeRay encrypts the token at rest, never returns it to the UI, and preserves it when the token field is left blank on a subsequent save.
3. Select a SeeRay goal and save the exact Microsoft custom event name configured for that UET conversion goal. The integration sends the goal's fixed value and destination currency.
4. Import a Microsoft Ads conversion CSV using the existing offline-conversion import workflow. Select the imported rows again in the Microsoft panel to preview the candidate batch.
5. Confirm that advertising-storage and conversion-measurement consent applies to every selected row. Review the live-send confirmation before submitting.

## Data and safeguards

- Each request contains at most 1,000 events. The UI only enables sending for recent eligible rows; the server independently requires event time within Microsoft's seven-day window (with a five-minute clock-skew allowance).
- Each row must match an imported conversion for this site, selected goal, and `microsoft_ads` platform. The raw MSCLKID is required at send time and must be a UUID. SeeRay's stored click ID and conversion ID remain site-scoped hashes; only the operator-reselected click ID is sent to Microsoft.
- The event includes a stable site-scoped `eventId` and `transactionId`, the configured event name, Unix event time, fixed goal value, currency, `adStorageConsent: G`, and `userData.msclkid`. No visitor email, phone, IP address, user agent, or raw SeeRay conversion ID is included.
- Sending is explicit and irreversible at the provider. A consent confirmation is required by the API as well as the UI. Provider errors are sanitized; the bearer token and raw provider response are not exposed in API errors.
- The preview is a local eligibility summary, not a provider dry run. Successful delivery means the provider accepted the batch; confirm conversion-goal matching and reporting in Microsoft Advertising.

## API surface

The site-scoped API is under `/api/v1/sites/{siteId}/offline-conversions/microsoft-ads`:

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/config` | Read destination metadata and goal mappings (never the token) |
| `PUT` / `DELETE` | `/config` | Connect, update, or disconnect the destination |
| `PUT` / `DELETE` | `/config/goals/{goalId}` | Add or remove a SeeRay-goal to Microsoft-event mapping |
| `POST` | `/send` | Send 1–1,000 selected imported rows after explicit consent confirmation |

Only workspace owners and admins can change configuration or send. Successful sends are recorded in the site audit log.

## Scope and acceptance

This connector currently covers imported offline conversions matched by MSCLKID; it is not a general website-event CAPI collector, automatic event forwarder, or Microsoft Ads account/goal discovery integration. It does not synchronize UET event IDs automatically with browser events. If the same conversion is also sent by UET, operators must account for Microsoft's deduplication requirements when designing their event IDs.

Automated tests cover configuration secrecy, imported-row/goal matching, consent gating, payload creation, and audit logging with a mocked provider gateway. A real UET tag/token, matching custom conversion goal, Microsoft account acceptance, and provider-side report verification are still required before claiming production acceptance.

For current endpoint, token, payload, identifier, consent, deduplication, and batch constraints, see [Microsoft Advertising Conversions API documentation](https://learn.microsoft.com/en-us/advertising/guides/uet-conversion-api-integration?view=bingads-13).
