# Workspace member management

Owners can open **Workspaces → Manage members** to view the team, add a user with an existing active account, change a member between Admin and Viewer, remove non-owners, or transfer ownership. Admins can view the directory; Viewers cannot enumerate workspace membership. The API enforces these rules independently of the admin UI.

- **Owner** manages members, workspace settings, and all site configuration.
- **Admin** can configure sites but cannot manage workspace membership or owner-only API tokens.
- **Viewer** can read analytics but cannot change site configuration.

Ownership is never assignable through the ordinary role selector. A deliberate transfer makes the selected member the Owner and demotes the current owner to Admin atomically. Owner removal or role downgrade is rejected until ownership is transferred, preventing an ownerless workspace.

The add-member workflow currently requires the user to have already registered; it does not send email invitations. Account invitations, SSO, site-scoped grants, and workspace access auditing remain separate work.
