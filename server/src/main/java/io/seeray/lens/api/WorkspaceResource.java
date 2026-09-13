package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceAccess;
import io.seeray.lens.domain.common.*;
import io.seeray.lens.domain.workspace.*;
import jakarta.transaction.Transactional;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.time.Instant;
import java.util.*;

@Authenticated
@Path("/api/v1/workspaces")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceResource {
    private final WorkspaceAccess access;

    public WorkspaceResource(WorkspaceAccess a) {
        access = a;
    }

    @GET
    public List<WorkspaceDto> list() {
        return OrganizationMember.<OrganizationMember>list("id.userId", access.userId()).stream()
                .map(m -> dto(m.organization, m.role))
                .toList();
    }

    @GET
    @Path("/{id}")
    public WorkspaceDto get(@PathParam("id") UUID id) {
        OrganizationMember m = access.member(id);
        return dto(m.organization, m.role);
    }

    @PATCH
    @Path("/{id}")
    @Transactional
    public WorkspaceDto update(@PathParam("id") UUID id, UpdateWorkspace r) {
        OrganizationMember m = access.require(id, WorkspaceRole.OWNER);
        if (r.name == null || r.name.isBlank())
            throw new ControlPlaneException(400, "INVALID_WORKSPACE", "Name is required");
        m.organization.name = r.name.trim();
        m.organization.updatedAt = Instant.now();
        return dto(m.organization, m.role);
    }

    static WorkspaceDto dto(Organization o, WorkspaceRole role) {
        return new WorkspaceDto(o.id, o.name, role.name().toLowerCase(Locale.ROOT));
    }

    public record UpdateWorkspace(@NotBlank @Size(max = 120) String name) {}

    public record WorkspaceDto(UUID id, String name, String role) {}
}
