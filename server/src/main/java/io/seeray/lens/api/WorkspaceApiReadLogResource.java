package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceReadAccessLogService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.UUID;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/api-read-log")
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceApiReadLogResource {
    private final WorkspaceReadAccessLogService log;

    public WorkspaceApiReadLogResource(WorkspaceReadAccessLogService log) {
        this.log = log;
    }

    @GET
    public WorkspaceReadAccessLogService.Page list(
            @PathParam("workspaceId") UUID workspaceId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("cursor") String cursor,
            @DefaultValue("25") @QueryParam("limit") int limit) {
        return log.list(workspaceId, from, to, cursor, limit);
    }
}
