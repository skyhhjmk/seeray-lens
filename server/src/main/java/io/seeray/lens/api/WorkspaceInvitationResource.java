package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceInvitationService;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/invitations")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceInvitationResource {
    private final WorkspaceInvitationService invitations;

    public WorkspaceInvitationResource(WorkspaceInvitationService invitations) {
        this.invitations = invitations;
    }

    @GET
    public WorkspaceInvitationService.ListResponse list(@PathParam("workspaceId") UUID workspaceId) {
        return invitations.list(workspaceId);
    }

    @POST
    public Response create(@PathParam("workspaceId") UUID workspaceId, CreateInvitationRequest request) {
        return Response.status(Response.Status.CREATED)
                .entity(invitations.create(workspaceId, request.email(), request.role()))
                .build();
    }

    @DELETE
    @Path("/{invitationId}")
    public Response revoke(@PathParam("workspaceId") UUID workspaceId, @PathParam("invitationId") UUID invitationId) {
        invitations.revoke(workspaceId, invitationId);
        return Response.noContent().build();
    }

    public record CreateInvitationRequest(@NotBlank @Email @Size(max = 320) String email, @NotBlank String role) {}
}
