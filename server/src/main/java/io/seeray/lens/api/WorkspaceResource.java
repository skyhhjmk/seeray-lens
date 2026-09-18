package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceAccess;
import io.seeray.lens.application.WorkspaceAuditRecorder;
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
    private final WorkspaceAuditRecorder audit;

    public WorkspaceResource(WorkspaceAccess a, WorkspaceAuditRecorder audit) {
        access = a;
        this.audit = audit;
    }

    @GET
    public List<WorkspaceDto> list() {
        return OrganizationMember.<OrganizationMember>list("id.userId", access.userId()).stream()
                .map(m -> dto(m.organization, m.role))
                .toList();
    }

    @POST
    @Transactional
    public Response create(CreateWorkspace request) {
        Instant now = Instant.now();
        Organization organization = new Organization();
        organization.id = UuidV7.next();
        organization.name = request.name.trim();
        organization.createdAt = now;
        organization.updatedAt = now;
        organization.persist();
        OrganizationMember member = new OrganizationMember();
        member.id = new OrganizationMemberId(organization.id, access.userId());
        member.organization = organization;
        member.user = io.seeray.lens.domain.auth.AppUser.findById(access.userId());
        member.role = WorkspaceRole.OWNER;
        member.createdAt = now;
        member.persist();
        audit.record(organization.id, member.user.id, "CREATE_WORKSPACE", "workspace", organization.id);
        return Response.status(Response.Status.CREATED)
                .entity(dto(organization, member.role))
                .build();
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
        audit.record(id, access.userId(), "UPDATE_WORKSPACE", "workspace", id);
        return dto(m.organization, m.role);
    }

    static WorkspaceDto dto(Organization o, WorkspaceRole role) {
        return new WorkspaceDto(o.id, o.name, role.name().toLowerCase(Locale.ROOT));
    }

    public record UpdateWorkspace(@NotBlank @Size(max = 120) String name) {}

    public record CreateWorkspace(@NotBlank @Size(max = 120) String name) {}

    public record WorkspaceDto(UUID id, String name, String role) {}
}
