# Google Search Console integration

Search performance is read live from the Google Search Console API; SeeRay stores only the selected property identifier. It does not persist Google tokens or service-account keys.

## Setup

1. Create a Google API project and enable Search Console API access as described in Google's [getting-started guide](https://developers.google.com/webmaster-tools/v1/getting-started).
2. Configure Google [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials) for the SeeRay server runtime. The integration requests the read-only `https://www.googleapis.com/auth/webmasters.readonly` scope.
3. Add the server identity to the Search Console property with read access. The property must be visible to that identity in [Sites: list](https://developers.google.com/webmaster-tools/v1/sites/list).
4. In the site Acquisition reports, open Search Console and save the exact property identifier: either a URL-prefix property such as `https://www.example.com/`, or a domain property such as `sc-domain:example.com`. Use **Test access** to check that Google exposes the property to the server identity.

## Report semantics

The report uses the Search Analytics `type=web` data and supports query, page, country, device, and date dimensions. It shows clicks, impressions, click-through rate, and average position. Search Console dates are interpreted in Pacific Time by Google. The report defaults to a period ending three days ago to reduce the chance of displaying still-processing dates; users can select up to 367 inclusive days.

Summary cards use a separate query with no dimensions, while the table requests up to 1,000 grouped rows. Google documents that the Search Analytics API returns top rows subject to internal limits and does not guarantee a complete set; anonymized queries can also be omitted. Therefore, row-table sums should not be treated as property totals. See [Search Analytics: query](https://developers.google.com/webmaster-tools/v1/searchanalytics/query) for API behavior and limitations.

No real Google property is exercised by automated tests. Production acceptance still requires an enabled API, working server ADC, and a property granted to the server identity.
