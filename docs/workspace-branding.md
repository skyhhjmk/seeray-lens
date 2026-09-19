# Workspace branding

Workspace owners can open **Branding** from the workspace selector and set a
display name, an accent color, and an optional HTTPS logo URL. The page includes
a live preview and preset color chips; it does not require editing JSON or
uploading credentials.

```text
GET   /api/v1/workspaces/{workspaceId}/branding
PATCH /api/v1/workspaces/{workspaceId}/branding
```

Branding is workspace-scoped. The display name is used in the admin shell and
site header, and the accent color drives the Material color scheme after the
workspace is selected. Empty fields restore SeeRay defaults. Logo URLs must be
HTTPS URLs with a hostname; data URLs, credentials, and fragments are rejected.

Reading is available to workspace members, while changing branding requires
the workspace owner. Updates are recorded as `UPDATE_WORKSPACE_BRANDING` in the
workspace activity log. Branding does not alter tracked-site data, tracker
origins, event payloads, or provider credentials.
