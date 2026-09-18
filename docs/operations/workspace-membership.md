# Workspace member management

Owners can open **Workspaces → Manage members** to view the team, add a user with an existing active account, [invite an email address](workspace-invitations.md), change a member between Admin and Viewer, remove non-owners, or transfer ownership. Admins can view members and invitation status; Viewers cannot enumerate workspace membership. The API enforces these rules independently of the admin UI.

Owners and Admins can also open **Workspace activity** from the workspace list. It records successful workspace and site creation, workspace setting changes, member/role/ownership changes, invitation creation/revocation/acceptance, and API-token creation/revocation. Entries are paged and date-filtered in UTC. Only the actor, action, resource type/ID, and timestamp are retained; request bodies, passwords, token values, invitation links, and read requests are not logged. Workspace activity is removed when the workspace itself is deleted.

The authenticated API is `GET /api/v1/workspaces/{workspaceId}/audit-log?from=YYYY-MM-DD&to=YYYY-MM-DD&limit=25&cursor=…`. It returns at most 100 metadata-only entries per page over a range of up to 366 days. Only Owners and Admins can read it.

- **Owner** manages members, workspace settings, and all site configuration.
- **Admin** can configure sites but cannot manage workspace membership or owner-only API tokens.
- **Viewer** can read analytics but cannot change site configuration.

Ownership is never assignable through the ordinary role selector. A deliberate transfer makes the selected member the Owner and demotes the current owner to Admin atomically. Owner removal or role downgrade is rejected until ownership is transferred, preventing an ownerless workspace.

The existing-account add flow grants access immediately. Email invitations are a separate opt-in flow: the invitee must accept the link, and the accepted account email must match the invited address. API-token usage history, login history, read-access auditing, SSO, and site-scoped grants remain separate work.
