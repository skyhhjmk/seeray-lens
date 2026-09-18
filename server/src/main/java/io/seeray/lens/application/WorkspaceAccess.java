package io.seeray.lens.application;

import io.quarkus.security.identity.SecurityIdentity;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.workspace.*;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.*;

@ApplicationScoped
public class WorkspaceAccess {
    private final SecurityIdentity identity;

    public WorkspaceAccess(SecurityIdentity identity) {
        this.identity = identity;
    }

    public UUID userId() {
        if (identity.isAnonymous()) throw new ControlPlaneException(401, "AUTH_INVALID_TOKEN", "Authentication failed");
        return UUID.fromString(identity.getPrincipal().getName());
    }

    public boolean isApiToken() {
        return ApiTokenAuthenticator.TYPE.equals(identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_TYPE));
    }

    public UUID apiTokenId() {
        return isApiToken() ? identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_ID) : null;
    }

    public UUID apiTokenWorkspaceId() {
        return isApiToken() ? identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_WORKSPACE_ID) : null;
    }

    public void requireInteractiveUser() {
        if (isApiToken())
            throw new ControlPlaneException(
                    403, "INTERACTIVE_USER_REQUIRED", "This action requires an interactive user session");
    }

    public OrganizationMember member(UUID workspaceId) {
        if (isApiToken() && !workspaceId.equals(apiTokenWorkspaceId()))
            throw new ControlPlaneException(404, "WORKSPACE_NOT_FOUND", "Workspace not found");
        OrganizationMember m = OrganizationMember.findById(new OrganizationMemberId(workspaceId, userId()));
        if (m == null) throw new ControlPlaneException(404, "WORKSPACE_NOT_FOUND", "Workspace not found");
        if (isApiToken()) {
            m = new OrganizationMember();
            m.id = new OrganizationMemberId(workspaceId, userId());
            m.organization = Organization.findById(workspaceId);
            m.user = io.seeray.lens.domain.auth.AppUser.findById(userId());
            m.role = Boolean.TRUE.equals(identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_CAN_WRITE))
                    ? WorkspaceRole.ADMIN
                    : WorkspaceRole.VIEWER;
        }
        return m;
    }

    public OrganizationMember require(UUID id, WorkspaceRole... roles) {
        OrganizationMember m = member(id);
        if (Arrays.stream(roles).noneMatch(r -> r == m.role))
            throw new ControlPlaneException(403, "FORBIDDEN", "Insufficient workspace permission");
        return m;
    }
}
