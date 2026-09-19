# Tag Manager API

The control plane exposes a site-scoped container API. Container versions are immutable; each environment points to one version independently. The existing `publishedVersion` field continues to represent production. Production publication and rollback require a second-person review; development and staging remain direct deployment targets.

Authenticated management endpoints:

```text
GET  /api/v1/sites/{siteId}/tag-manager/containers
POST /api/v1/sites/{siteId}/tag-manager/containers
GET  /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/versions
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/versions
GET  /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/script-policy
PUT  /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/script-policy
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/versions/{version}/environments/{environment}/publish
GET  /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/production-requests
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/production-requests
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/production-requests/{requestId}/approve
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/production-requests/{requestId}/reject
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/production-requests/{requestId}/cancel
GET  /api/v1/sites/{siteId}/tag-manager/templates
POST /api/v1/sites/{siteId}/tag-manager/templates
PUT  /api/v1/sites/{siteId}/tag-manager/templates/{templateId}
DELETE /api/v1/sites/{siteId}/tag-manager/templates/{templateId}
POST /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/preview-sessions
GET  /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/preview-sessions/{sessionId}/events
DELETE /api/v1/sites/{siteId}/tag-manager/containers/{containerId}/preview-sessions/{sessionId}
```

The version body is a JSON array. The public endpoint returns the array released to the requested environment (production by default):

```text
GET /api/v1/tag-manager/{trackingId}/container
Origin: https://your-site.example
```

Use `?environment=development`, `?environment=staging`, or `?environment=production` to select a release. Invalid environment names are rejected. Existing production releases are migrated and remain the default. Development and staging accept direct deployment of any immutable version; redeploying an older version rolls back only that environment. Production changes—including rollback—must use a release request, and the legacy `/versions/{version}/publish` route returns `409 PRODUCTION_APPROVAL_REQUIRED` instead of bypassing review.

The graphical panel requires a release summary when a workspace owner/admin requests production. The request snapshots the current production version as its review base and permits only one pending request per container. A different workspace owner/admin must approve or reject it; the requester cannot approve their own change. Rejection requires an explanation, while approval may include an optional note. If the production base no longer matches at approval time, the request is blocked as stale and must be resubmitted. Requesters/admins can withdraw a pending request. The approvals panel shows author, purpose, base/target versions, added/changed/removed tag names, trigger summaries, and whether custom script changed—never a raw JSON diff or the script body. Successful request, approval, rejection, cancellation, and deployment mutations are recorded in the site audit log.

The public request requires an `Origin` matching an enabled site allowed domain (or an enabled subdomain rule). Unknown tracking IDs and disallowed origins are rejected; no published container is returned without that check.

The graphical tag editor also has **Test on live site**. It creates a 15-minute session from the current unsaved draft, then shows a copyable test snippet and a live event log. The snippet must run on a page whose browser `Origin` is allowed for the site. Start in safe mode: normal SeeRay collection, heatmap capture, and experiment loading are disabled; event tags are simulated and custom HTML/JavaScript plus custom-JavaScript trigger functions are marked blocked. The operator can explicitly opt into executing custom code after seeing a warning. That code runs in the test page and may change it or send requests to third parties.

Management creates the session with `{ "tags": [...], "executeCustomCode": false }`. The response includes a session ID, expiry, and a random bearer token shown only once. Only a SHA-256 hash of that token is stored. The browser fetches the snapshot and posts debug results using `Authorization: Bearer <token>` to:

```text
GET  /api/v1/tag-manager/{trackingId}/preview/{sessionId}
POST /api/v1/tag-manager/{trackingId}/preview/{sessionId}/events
```

The event endpoint accepts an array of `{ tagIndex, triggerEvent, outcome, pagePath }` records. It does not accept event properties or visitor identifiers. The server derives tag names from the stored draft and strips query strings and fragments from page paths. Logs are capped at 1,000 per session and the admin UI shows the newest 100. Stop the session from the dialog to revoke it early; expired sessions are also deleted by a scheduled cleanup job. The token is a temporary testing credential: use it only on a controlled test page and remove the snippet when finished.

The admin panel lists versions and provides a deployment control for development, staging, and production, showing each environment's active version. Its production install snippet uses the backward-compatible default; the staging snippet sets `data-tag-manager-environment="staging"`. It also offers an organization-shared template library: create and edit one or more tags with the visual tag editor, add a short usage description, and insert a template into a selected container as a new draft. Templates never publish on their own, and deleting one does not affect versions that already used it. The API accepts JSON, while the admin panel provides a horizontal three-column editor: settings, multi-select triggers, and injected code. The tracker executes these tag forms:

Template tags use the same supported tag types, trigger rules, validation limits, and execution behavior as container tags. Template names are unique within a workspace. The template API is site-scoped for access control, but the library is shared by all sites in the same workspace.

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

Custom event triggers can also filter on values from the event's `properties`. Conditions within one trigger are combined with AND; the trigger list remains OR. The graphical editor provides a property key, match rule, and value control for each filter—no condition JSON is needed:

```json
{
  "type": "event",
  "event": "signup",
  "conditions": [
    {"property": "plan", "operator": "equals", "value": "pro"},
    {"property": "campaign", "operator": "starts_with", "value": "spring_"}
  ]
}
```

Supported match rules are `equals`, `not_equals`, `contains`, `starts_with`, `ends_with`, and `exists`. Comparisons are case-sensitive. A missing or null event property does not satisfy a value comparison (including `not_equals`); use `exists` to check presence. String, number, and boolean values can be compared; nested objects and arrays do not match value rules. Each event trigger accepts at most 20 filters, and event property keys/values are limited to 128/512 characters.

For a custom JavaScript trigger, the final call is `window.shouldFireMarketingPixel(event, context)`. The function must be mounted on `window` and return `true`; if `code` is supplied, the tracker evaluates the function expression and mounts it under that name first. A page can also define the function itself before the tracker event fires:

```js
window.shouldFireMarketingPixel = (event, context) =>
  event.event === 'purchase' && context.url.includes('/checkout');
```

Drafts are validated before a version is created: at most 100 tags and 64 KiB of UTF-8 JSON, with `type` set to `event`, `page_view`, or `custom_html`. Custom snippets require a name, at least one trigger, and non-empty code up to 32 KiB. Custom trigger functions require a function name and optional code up to 16 KiB; `properties` must be an object. Unsupported types, malformed triggers, and oversized definitions are rejected with `INVALID_TAG_CONTAINER`.

Event tags fire when `SeeRay.push({event: 'signup'})` is called; `page_view` tags run on a page-view trigger. Custom snippets insert HTML into the page and execute `script` tags (or raw JavaScript) when their trigger fires. Because snippets execute in the visitor's page context, publish only code you trust and account for the site's CSP.

### Event property variables

For event and page-view tags, string values in the graphical **Event properties** editor can include variables. Use **Insert variable** beside a value to add one; variables are resolved when a trigger fires and only affect the emitted event properties. Available variables are:

- Page URL, page title, and referrer
- Trigger event, event name, category, action, and a named event property (`{{Event Property: plan}}`)
- Browser, operating system, device type, language, screen size, and viewport size

For example, configure `landing_page` as `{{Page URL}}` and `source_plan` as `{{Event Property: plan}}`. Event properties supplied to `SeeRay.push()` remain available, while values configured on the tag override same-key event properties after variable resolution. Unknown variable names are preserved literally so a configuration mistake is visible in the resulting event. Variables are not interpolated into custom HTML or JavaScript; code snippets remain explicit code and are clearly marked in production review.

### Script governance

The **Script governance** action on each container opens a normal settings form
for the container's script policy. Owners and admins can disable all custom HTML
and JavaScript tags, or keep them enabled while entering an allowlist of external
`http(s)` origins (one origin per line, without paths or query strings). The
default policy preserves existing containers: custom code is enabled and an empty
allowlist means no external-origin restriction until an administrator chooses to
tighten it.

The server enforces this policy when creating a draft, creating a live preview,
deploying development/staging, and requesting production approval. It also
rechecks the policy at approval time, so changing the policy cannot be bypassed
by reusing an older draft. Disallowed custom code returns
`TAG_SCRIPT_POLICY_CUSTOM_CODE_BLOCKED`; an external URL outside the allowlist
returns `TAG_SCRIPT_POLICY_ORIGIN_BLOCKED`. Policy changes are ordinary
site-scoped Tag Manager mutations and therefore appear in the audit log.

### Draft dry-run

Choose **Preview draft** in the tag editor to simulate a visitor event against the current unsaved draft. The preview lets the operator set the event, page metadata, event properties, and sample visitor context, then shows which tags match—including event-property filters—and the event properties that would be emitted after variable resolution. It sends no request and never executes custom code. Choose **Test on live site** when you need the real browser to evaluate selectors, page context, or custom JavaScript triggers; this uses the short-lived session described above and records only the bounded, query-stripped debug log. Neither preview mode publishes the draft.
