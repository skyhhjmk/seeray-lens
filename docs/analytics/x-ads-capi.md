# X Ads Conversions API export

SeeRay can send an explicitly selected set of already-imported `x_ads` offline
conversion rows to the X Ads Conversions API. This is a live server-to-server
send; it cannot be undone in X Ads.

## Configure

1. In X Ads Events Manager, create or select the X Pixel and create a code-based
   conversion event for each SeeRay goal you intend to send.
2. Generate an X Conversion API access token for that Pixel.
3. In SeeRay's Offline conversion attribution page, save the Pixel ID, the
   ad-account ISO currency, and the access token. The token is encrypted at
   rest and is never returned to the Admin client.
4. Select a SeeRay goal and map it to the event ID shown in Events Manager.
5. Import a CSV with `platform=x_ads` containing the conversion ID, raw `twclid`,
   and offset-qualified conversion timestamp. Then select the matching imported
   rows in the X Ads panel, confirm permission for ad-storage and conversion
   measurement, and explicitly confirm the live send.

The service accepts at most 2,000 rows per send. Before sending, it rechecks the
site, goal, exact imported conversion/click-ID pair, consent confirmation, and a
tracked X click on the same site within X's documented maximum 30-day click
attribution window. Requests contain only `twclid` as the matching identifier;
they do not contain email, phone, IP address, user agent, visitor ID, or session
ID. Stored click and conversion identifiers remain site-scoped hashes.

SeeRay sends the mapped Events Manager `event_id`, a stable site-scoped
`conversion_id`, the conversion timestamp in milliseconds, the configured
currency, and the selected goal's fixed value when present. The stable
`conversion_id` helps make retries recognizable; pixel/CAPI deduplication only
works if the same conversion ID is also used for the corresponding Pixel event.

## Provider contract and acceptance

The request follows X's official server-side GTM template:

- `POST https://ads-api.x.com/12/measurement/conversions/{pixel_id}`
- `X-Pixel-Token` authentication
- a JSON body with a `conversions` array, `conversion_timestamp` in epoch
  milliseconds, `identifiers: [{"twclid": "..."}]`, `event_id`,
  `conversion_id`, `value`, and `price_currency`

References: [X's official server-side template](https://github.com/twitter/x-ads-conversion-api-gtm-template/blob/main/template.tpl),
[X website conversion tracking](https://business.x.com/en/help/campaign-measurement-and-analytics/conversion-tracking-for-websites),
and [X website conversions campaign attribution windows](https://business.x.com/en/help/campaign-setup/create-website-conversions-campaign).

Automated integration tests verify configuration encryption, mapping,
same-site tracked-click matching, consent enforcement, privacy-minimal payload,
and audit metadata with a stubbed provider gateway. A live X Ads account/API
acceptance and Admin browser acceptance are still required before claiming
production provider parity.
