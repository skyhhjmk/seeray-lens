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

    public OrganizationMember member(UUID workspaceId) {
        OrganizationMember m = OrganizationMember.findById(new OrganizationMemberId(workspaceId, userId()));
        if (m == null) throw new ControlPlaneException(404, "WORKSPACE_NOT_FOUND", "Workspace not found");
        return m;
    }

    public OrganizationMember require(UUID id, WorkspaceRole... roles) {
        OrganizationMember m = member(id);
        if (Arrays.stream(roles).noneMatch(r -> r == m.role))
            throw new ControlPlaneException(403, "FORBIDDEN", "Insufficient workspace permission");
        return m;
    }
}
