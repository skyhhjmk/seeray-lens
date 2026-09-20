package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.SiteService;
import io.seeray.lens.application.WorkspaceAccess;
import io.seeray.lens.application.WorkspaceAuditRecorder;
import io.seeray.lens.domain.site.Site;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.util.*;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/sites")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceSiteResource {
    private final SiteService sites;
    private final WorkspaceAuditRecorder audit;
    private final WorkspaceAccess access;

    public WorkspaceSiteResource(SiteService sites, WorkspaceAuditRecorder audit, WorkspaceAccess access) {
        this.sites = sites;
        this.audit = audit;
        this.access = access;
    }

    @GET
    public List<SiteResource.SiteDto> list(@PathParam("workspaceId") UUID workspaceId) {
        return sites.list(workspaceId).stream().map(SiteResource::dto).toList();
    }

    @POST
    @Transactional
    public Response create(@PathParam("workspaceId") UUID workspaceId, SiteResource.SiteRequest request) {
        Site site = sites.create(
                workspaceId,
                request.name(),
                request.timezone(),
                request.defaultLanguage(),
                request.rawRetentionDays(),
                request.aggregateRetentionDays(),
                request.requireConsent(),
                request.fingerprintRiskEnabled(),
                request.fingerprintRetentionDays());
        audit.record(workspaceId, access.userId(), "CREATE_SITE", "site", site.id);
        return Response.status(Response.Status.CREATED)
                .entity(SiteResource.dto(site))
                .build();
    }
}
