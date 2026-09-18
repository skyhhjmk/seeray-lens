package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceAuditLogService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.UUID;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/audit-log")
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceAuditLogResource {
    private final WorkspaceAuditLogService auditLog;

    public WorkspaceAuditLogResource(WorkspaceAuditLogService auditLog) {
        this.auditLog = auditLog;
    }

    @GET
    public WorkspaceAuditLogService.Page list(
            @PathParam("workspaceId") UUID workspaceId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("cursor") String cursor,
            @DefaultValue("25") @QueryParam("limit") int limit) {
        return auditLog.list(workspaceId, from, to, cursor, limit);
    }
}
