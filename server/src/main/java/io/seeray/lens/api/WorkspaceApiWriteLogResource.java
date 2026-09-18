package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceWriteAccessLogService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.UUID;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/api-write-log")
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceApiWriteLogResource {
    private final WorkspaceWriteAccessLogService log;

    public WorkspaceApiWriteLogResource(WorkspaceWriteAccessLogService log) {
        this.log = log;
    }

    @GET
    public WorkspaceWriteAccessLogService.Page list(
            @PathParam("workspaceId") UUID workspaceId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("cursor") String cursor,
            @DefaultValue("25") @QueryParam("limit") int limit) {
        return log.list(workspaceId, from, to, cursor, limit);
    }
}
