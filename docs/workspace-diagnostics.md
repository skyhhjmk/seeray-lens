# Workspace system diagnostics

Owners and workspace admins can open **System diagnostics** from the workspace
selector. The page is intentionally read-only: it checks control-plane
connectivity and configuration without reading event payloads or revealing
credentials.

```text
GET /api/v1/workspaces/{workspaceId}/diagnostics
```

The endpoint requires an interactive owner/admin session. API tokens and
viewers cannot use it. The response contains an overall status, the check time,
and a stable list of checks:

- `database`: confirms the control plane can query the database.
- `sites`: reports whether the workspace has any sites.
- `tracking`: reports how many sites have collection enabled.
- `origins`: finds sites without an enabled tracker origin, which would cause
  browser origin checks to reject collection or Tag Manager delivery.
- `retention`: detects invalid raw/aggregate retention relationships before a
  retention job can produce surprising results.
- `release`: reports the configured release identifier and the number of
  applied database migrations. Migrations are still applied by the server at
  startup; this check makes upgrade readiness visible without pretending to
  execute a remote upgrade.

Each warning or error includes a recommended next action. A healthy response is
not a production acceptance claim: queue health, browser/device behavior,
external provider authorization, and deployment state still require their own
runtime checks.
