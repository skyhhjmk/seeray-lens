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

Publishing an older version is the rollback operation; the admin panel lists all versions and can publish any draft or previously published version. The current payload is intentionally JSON-oriented so the admin can evolve tag, trigger, and variable schemas without a database migration. The tracker executes only these safe tag forms:

```json
{
  "type": "event",
  "trigger": "signup",
  "eventType": "tag_signup",
  "name": "signup_tag"
}
```

The tag fires when `SeeRay.push({event: 'signup'})` is called. `page_view` tags can run on a page-view trigger. HTML and arbitrary scripts are ignored. Preview, rollback, rich variables, and broader tag governance remain follow-up work.
