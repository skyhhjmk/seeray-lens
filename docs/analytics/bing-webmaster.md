# Bing Webmaster Tools integration

SeeRay reads Bing organic-search reporting live through the Bing Webmaster Tools JSON/HTTP API. A site URL and its Bing API key are stored per SeeRay site; the key is encrypted with AES-256-GCM and is never returned to the admin client. Google Search Console uses server-side ADC and does not share these credentials.

## Server setup

1. Configure a stable, private encryption key before saving any third-party credentials:

   ```sh
   openssl rand -base64 32
   ```

   Set the generated value as `SEERAY_SECRET_ENCRYPTION_KEY` in the server runtime. Keep it stable across restarts and backups. If the key is lost or changed, saved integration credentials cannot be decrypted and must be entered again. Do not use the test-only value from `server/src/main/resources/application.properties` in a deployed environment.

2. Create a Bing Webmaster API key for a trusted Microsoft account. Microsoft's guidance recommends OAuth where available and warns against giving API keys to untrusted parties. A key belongs to a user, not a single site, and can access that user's other verified sites. Use a dedicated account with only the properties intended for SeeRay where possible.
3. In the site's Acquisition reports, open **Bing Webmaster**, enter the exact URL shown by Bing (for example `https://www.example.com/`) and the API key, then choose **Test access**. For a later key rotation, enter the replacement key; leave the field blank to retain the saved key. Removing the connection deletes the encrypted credential.
4. The API sends the key in a query parameter as required by Bing's JSON protocol. SeeRay does not include request URLs or provider response bodies in application errors. Ensure reverse proxies, HTTP access logs, traces, and outbound diagnostics redact the `apikey` query parameter.

## Report semantics and limits

The report supports query, page, and date views with clicks, impressions, and CTR. Average impression position is shown for query/page rows when supplied by Bing. Summary cards use daily rank-and-traffic statistics; the rows table aggregates the selected provider breakdown. Bing query and page statistics are updated weekly and the API returns provider-selected top rows, so row sums may not equal summary totals. These methods do not provide country or device dimensions. Date selection is limited to the latest six months, ends no later than today, and defaults to a period ending three days ago.

The integration uses Bing's JSON/HTTP protocol. SOAP and POX variants were retired on August 31, 2026, so those protocols are intentionally not used. See Microsoft's [API protocol documentation](https://learn.microsoft.com/en-us/bingwebmaster/api-protocols), [access guidance](https://learn.microsoft.com/en-us/bingwebmaster/getting-access), [`GetRankAndTrafficStats`](https://learn.microsoft.com/en-us/dotnet/api/microsoft.bing.webmaster.api.interfaces.iwebmasterapi.getrankandtrafficstats?view=bing-webmaster-dotnet), [`GetQueryStats`](https://learn.microsoft.com/en-us/dotnet/api/microsoft.bing.webmaster.api.interfaces.iwebmasterapi.getquerystats?view=bing-webmaster-dotnet), and [`GetPageStats`](https://learn.microsoft.com/en-us/dotnet/api/microsoft.bing.webmaster.api.interfaces.iwebmasterapi.getpagestats?view=bing-webmaster-dotnet).

Automated tests use a mocked Bing gateway and do not exercise a real Bing property. Production acceptance still requires a valid user API key, an exact verified site URL, the encryption key configured in the server runtime, and validation against Bing.
