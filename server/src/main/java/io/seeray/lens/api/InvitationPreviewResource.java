package io.seeray.lens.api;

import io.seeray.lens.application.WorkspaceInvitationService;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.regex.Pattern;

@Path("/api/v1/auth/invitations")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class InvitationPreviewResource {
    private static final Pattern TOKEN = Pattern.compile("[A-Za-z0-9_-]{1,128}");
    private final WorkspaceInvitationService invitations;

    public InvitationPreviewResource(WorkspaceInvitationService invitations) {
        this.invitations = invitations;
    }

    @POST
    @Path("/preview")
    public WorkspaceInvitationService.InvitationSummary preview(PreviewRequest request) {
        String token = request.token();
        if (!TOKEN.matcher(token).matches()) {
            return invitations.preview("");
        }
        return invitations.preview(token);
    }

    public record PreviewRequest(@NotBlank @Size(max = 128) String token) {}
}
