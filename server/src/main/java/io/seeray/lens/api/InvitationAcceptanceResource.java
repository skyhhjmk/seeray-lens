package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceInvitationService;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Authenticated
@Path("/api/v1/workspace-invitations")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class InvitationAcceptanceResource {
    private final WorkspaceInvitationService invitations;

    public InvitationAcceptanceResource(WorkspaceInvitationService invitations) {
        this.invitations = invitations;
    }

    @POST
    @Path("/accept")
    public WorkspaceInvitationService.AcceptResult accept(AcceptInvitationRequest request) {
        return invitations.acceptForCurrentUser(request.invitationToken());
    }

    public record AcceptInvitationRequest(@NotBlank @Size(max = 128) String invitationToken) {}
}
