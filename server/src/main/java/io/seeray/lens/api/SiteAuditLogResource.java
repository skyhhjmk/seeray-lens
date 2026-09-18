package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.SiteAuditLogService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/audit-log")
@Produces(MediaType.APPLICATION_JSON)
public class SiteAuditLogResource {
    private final SiteAuditLogService auditLog;

    public SiteAuditLogResource(SiteAuditLogService auditLog) {
        this.auditLog = auditLog;
    }

    @GET
    public SiteAuditLogService.Page list(
            @PathParam("siteId") UUID siteId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("cursor") String cursor,
            @DefaultValue("25") @QueryParam("limit") int limit) {
        return auditLog.list(siteId, from, to, cursor, limit);
    }
}
