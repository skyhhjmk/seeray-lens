# Yandex Webmaster integration

SeeRay reads Yandex organic-search query statistics through Webmaster API v4. Site URLs and OAuth access tokens are stored per SeeRay site; tokens are encrypted at rest using the operator-managed `SEERAY_SECRET_ENCRYPTION_KEY` and are never returned to the admin client.

## Yandex application and token setup

1. Register a Yandex OAuth application with Webmaster access. Yandex's current integration terms require a registered client ID and a partner agreement; the app setup guide lists the Webmaster scopes needed for site information and verification. Approval and client registration are Yandex-side prerequisites, not created by SeeRay.
2. Authorize the Yandex account that owns the verified site. Yandex's Webmaster guide documents the authorization URL as `https://oauth.yandex.com/authorize?response_type=token&client_id=<client-id>` and says its access token is valid for six months. Treat the token as a password. Never put it in URLs or source control.
3. In the site's Acquisition reports, open **Yandex Webmaster**, enter the exact ASCII site URL and OAuth client ID. Use **Copy authorization link**, open it in a browser, authorize the account, and paste the returned OAuth token. **Save & verify** checks the token, resolves its Yandex user ID, and requires an exact matching verified site before saving. The client ID is not stored. The token can be left blank to retain it or replaced after reauthorization.
4. Configure a stable, private base64-encoded 32-byte `SEERAY_SECRET_ENCRYPTION_KEY` in the server runtime. See [Bing Webmaster setup](bing-webmaster.md#server-setup) for key generation, backup, and rotation behavior; both integrations use the same server key.

## Report semantics and limits

The report shows search queries, clicks, impressions, CTR and average display position for the selected interval. Device filtering supports all devices, desktop, mobile/tablet, mobile, or tablet. Query rows are sorted by impressions, and CSV exports the visible result set. The API returns provider-ranked popular queries (up to 3,000, requested in pages of at most 500); SeeRay marks potentially truncated results and does not claim the row sum is a complete property total. The selected interval is capped at 366 days. The popular-queries endpoint does not provide a per-day trend or a page breakdown, so the UI does not invent either.

Yandex requires an OAuth token in the `Authorization: OAuth …` header, a user ID from `/v4/user`, and a host ID from the user's host list. See the official [authorization guide](https://yandex.com/dev/webmaster/doc/en/tasks/how-to-get-oauth), [API terms and client registration requirements](https://yandex.com/dev/webmaster/doc/en/), [popular-query API](https://yandex.com/dev/webmaster/doc/en/reference/host-search-queries-popular), and [host list API](https://yandex.com/dev/webmaster/doc/en/reference/hosts).

Automated tests use a mocked gateway and do not exercise Yandex credentials or a live property. Production acceptance still requires an approved Yandex OAuth application, a current token, a verified property, and a successful live query.
