# Workspace API tokens

API tokens provide server-to-server access without reusing a person's login session. Create and revoke them from **Workspace API tokens** in the admin app. Only a workspace owner can manage tokens; the full token is shown once when it is created.

## Permissions and boundaries

- `sites:read` permits GET/HEAD/OPTIONS requests to site-scoped `/api/v1/sites/{siteId}/...` APIs and read-only workspace/site discovery for the token's own workspace.
- `sites:write` permits site-scoped mutations as well as reads. It also implies `sites:read`.
- Tokens cannot create workspaces, manage members/invitations/tokens, change workspace settings, or use unrelated account APIs.
- A site in another workspace is not accessible. The token is also invalidated when its creating user is disabled or removed from that workspace.
- A revoked or expired token immediately stops authenticating. The settings page reports its creation, expiry, and last-used time, and can expand each token to inspect its recent request method, route template, response status and timestamp. Request history is retained for 30 days. Query strings, request bodies, response bodies, credentials, IP addresses and user-agent values are not recorded.

## Usage

Store the token in a server-side secret manager or environment variable. Do not put it in browser code, source control, URLs, or logs.

```sh
export SEERAY_API_TOKEN='srlat_...'
curl --fail-with-body \
  -H "Authorization: Bearer $SEERAY_API_TOKEN" \
  'https://YOUR_SEERAY_HOST/api/v1/sites/YOUR_SITE_ID/analytics/overview?from=2026-09-01&to=2026-09-18'
```

Use a read-only token unless the integration needs to change site configuration. Rotate by creating a replacement, updating the secret in the client, verifying it, and then revoking the old token.
