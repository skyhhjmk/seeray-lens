package io.seeray.lens.api;

import io.seeray.lens.application.WorkspaceInvitationService;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.regex.Pattern;

@Path("/api/v1/auth/invitations")
@Produces(MediaType.APPLICATION_JSON)
public class InvitationPreviewResource {
    private static final Pattern TOKEN = Pattern.compile("[A-Za-z0-9_-]{1,128}");
    private final WorkspaceInvitationService invitations;

    public InvitationPreviewResource(WorkspaceInvitationService invitations) {
        this.invitations = invitations;
    }

    @GET
    @Path("/{token}")
    public WorkspaceInvitationService.InvitationSummary preview(@PathParam("token") String token) {
        if (!TOKEN.matcher(token).matches()) {
            return invitations.preview("");
        }
        return invitations.preview(token);
    }
}
