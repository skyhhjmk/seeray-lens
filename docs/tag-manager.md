# Tag Manager API

The control plane exposes a site-scoped container API. Container versions are immutable drafts; publishing a version demotes the previous published version to `draft`.

Authenticated management endpoints:

```text
GET  /api/v1/sites/{siteId}/tag-manager/containers
POST /api/v1/sites/{siteId}/tag-manager/containers
GET  /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/versions
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/versions
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/versions/{version}/publish
```

The version body is a JSON array. The public endpoint returns the latest published array:

```text
GET /api/v1/tag-manager/{trackingId}/container
Origin: https://your-site.example
```

The public request requires an `Origin` matching an enabled site allowed domain (or an enabled subdomain rule). Unknown tracking IDs and disallowed origins are rejected; no published container is returned without that check.

Publishing an older version is the rollback operation; the admin panel lists all versions and can publish any draft or previously published version. The API accepts JSON, while the admin panel provides a horizontal three-column editor: settings, multi-select triggers, and injected code. The tracker executes these tag forms:

The admin editor is graphical: choose the tag type, trigger, event fields, and optional key/value properties in a form. Existing latest-version values are loaded into the form before creating the next draft; operators do not need to edit JSON directly.

```json
{
  "type": "event",
  "trigger": "signup",
  "eventType": "tag_signup",
  "name": "signup_tag"
}
```

A custom HTML/JavaScript tag stores the code snippet together with one or more triggers. Trigger objects can be predefined events, custom event names, or a custom JavaScript function. Predefined and custom event triggers use OR semantics:

```json
{
  "type": "custom_html",
  "name": "Marketing pixel",
  "triggers": [
    {"type": "predefined", "event": "page_view"},
    {"type": "event", "event": "signup"},
    {
      "type": "custom_js",
      "functionName": "shouldFireMarketingPixel",
      "code": "(event, context) => event.event === 'purchase'"
    }
  ],
  "code": "<script>window.marketingReady = true;</script>"
}
```

For a custom JavaScript trigger, the final call is `window.shouldFireMarketingPixel(event, context)`. The function must be mounted on `window` and return `true`; if `code` is supplied, the tracker evaluates the function expression and mounts it under that name first. A page can also define the function itself before the tracker event fires:

```js
window.shouldFireMarketingPixel = (event, context) =>
  event.event === 'purchase' && context.url.includes('/checkout');
```

Drafts are validated before a version is created: at most 100 tags and 64 KiB of UTF-8 JSON, with `type` set to `event`, `page_view`, or `custom_html`. Custom snippets require a name, at least one trigger, and non-empty code up to 32 KiB. Custom trigger functions require a function name and optional code up to 16 KiB; `properties` must be an object. Unsupported types, malformed triggers, and oversized definitions are rejected with `INVALID_TAG_CONTAINER`.

Event tags fire when `SeeRay.push({event: 'signup'})` is called; `page_view` tags run on a page-view trigger. Custom snippets insert HTML into the page and execute `script` tags (or raw JavaScript) when their trigger fires. Because snippets execute in the visitor's page context, publish only code you trust and account for the site's CSP. Preview, rich variables, and broader tag governance remain follow-up work.
