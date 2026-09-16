# Tag Manager API

The control plane exposes a site-scoped container API. Container versions are immutable drafts; publishing a version demotes the previous published version to `draft`.

Authenticated management endpoints:

```text
GET  /api/v1/sites/{siteId}/tag-manager/containers
POST /api/v1/sites/{siteId}/tag-manager/containers
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/versions
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/versions/{version}/publish
```

The version body is a JSON array. The public endpoint returns the latest published array:

```text
GET /api/v1/tag-manager/{trackingId}/container
Origin: https://your-site.example
```

The public request requires an `Origin` matching an enabled site allowed domain (or an enabled subdomain rule). Unknown tracking IDs and disallowed origins are rejected; no published container is returned without that check.

The current payload is intentionally JSON-oriented so the admin can evolve tag, trigger, and variable schemas without a database migration. Typed tag execution, preview, rollback, and the admin editor remain follow-up work.
