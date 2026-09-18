package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceAuthActivityLogService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.UUID;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/auth-activity")
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceAuthActivityResource {
    private final WorkspaceAuthActivityLogService activity;

    public WorkspaceAuthActivityResource(WorkspaceAuthActivityLogService activity) {
        this.activity = activity;
    }

    @GET
    public WorkspaceAuthActivityLogService.Page list(
            @PathParam("workspaceId") UUID workspaceId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("cursor") String cursor,
            @DefaultValue("25") @QueryParam("limit") int limit) {
        return activity.list(workspaceId, from, to, cursor, limit);
    }
}
