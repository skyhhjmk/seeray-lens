# Workspace email invitations

Workspace owners can invite a new or existing account from **Workspaces → Manage members → Invite**. Select Admin or Viewer; Owner is never assignable by invitation. Admins can see invitation status but cannot create or revoke invitations. Existing accounts continue to be addable immediately through **Add member**.

Invitations expire after seven days and can be accepted once. The email link uses the Flutter hash route, so its token remains in the URL fragment and is not sent to the web host. The admin exchanges it in a JSON request body for a preview, keeping it out of ordinary access-log URLs. The preview shows the workspace, invited address, role, and expiry. An existing user signs in with the invited email before accepting. A new user can register from the same page; invitation registration creates only the invited workspace membership, not a separate personal workspace. The server stores only a SHA-256 token hash. Owners can revoke a pending invitation, which immediately invalidates its link. Expired, accepted, and revoked invitations remain visible in the workspace directory for status history.

Configure the public admin URL and SMTP delivery in the server environment:

- `SEERAY_ADMIN_URL`: public base URL of the admin app, without a route (for example `https://analytics.example.com`). The invitation path is appended automatically. The default is for local development only.
- `SEERAY_SMTP_HOST`, `SEERAY_SMTP_PORT`, `SEERAY_SMTP_USERNAME`, `SEERAY_SMTP_PASSWORD`, and `SEERAY_SMTP_FROM`: SMTP server, credentials, and sender. Use a verified sender address.
- `SEERAY_SMTP_STARTTLS` and `SEERAY_SMTP_TLS`: Quarkus mail transport security settings; keep production SMTP encrypted and consistent with the mail provider.

If mail delivery fails, invitation creation returns an error and the database transaction is rolled back, so the owner can safely correct SMTP configuration and retry. Never put invitation tokens in support tickets or logs.

The API is available at:

- `GET /api/v1/workspaces/{workspaceId}/invitations` for owner/admin status listing.
- `POST /api/v1/workspaces/{workspaceId}/invitations` for owner-only creation with `{ "email": "person@example.com", "role": "viewer" }`.
- `DELETE /api/v1/workspaces/{workspaceId}/invitations/{invitationId}` for owner-only revocation of a pending invitation.
- `POST /api/v1/auth/invitations/preview` for the public invitation preview with `{ "token": "…" }`.
- `POST /api/v1/workspace-invitations/accept` for an authenticated matching account, or `POST /api/v1/auth/register-invitation` to register and accept in one transaction.
