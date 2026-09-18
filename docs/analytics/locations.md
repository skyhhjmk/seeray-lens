# Visitor location reports

The locations report groups visits and distinct visitors by country, continent, region, and city. It uses the first page-view event in each visit and honors the same date range and saved segment as the other analytics reports.

Location collection is disabled by default. Enable it only when requests arrive through a proxy you control:

```text
SEERAY_GEO_LOCATION_ENABLED=true
SEERAY_GEO_TRUSTED_PROXY_CIDRS=<exact immediate-proxy CIDRs>
```

For Cloudflare, configure its IP Geolocation and location managed transforms to set `CF-IPCountry`, `CF-IPContinent`, `CF-Region-Code`, `CF-Region`, `CF-IPCity`, and `CF-Timezone`. The collector accepts those headers only when the directly connected peer address matches a configured trusted-proxy CIDR; browser-supplied values are ignored. Keep the trusted list limited to the actual edge proxy addresses and verify the network path before enabling collection.

The collector retains only validated coarse location dimensions on the visit fact, never the client IP. Country is required for a location record; region, city, and timezone are optional. IP-based locations are estimates and can be missing or inaccurate, especially when users use VPNs, mobile carriers, privacy relays, or anonymizing proxies. Existing visits are not backfilled.
