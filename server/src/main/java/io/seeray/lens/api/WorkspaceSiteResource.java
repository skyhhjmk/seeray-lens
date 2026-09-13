package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.SiteService;
import io.seeray.lens.domain.site.Site;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.util.*;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/sites")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceSiteResource {
    private final SiteService sites;

    public WorkspaceSiteResource(SiteService sites) {
        this.sites = sites;
    }

    @GET
    public List<SiteResource.SiteDto> list(@PathParam("workspaceId") UUID workspaceId) {
        return sites.list(workspaceId).stream().map(SiteResource::dto).toList();
    }

    @POST
    public Response create(@PathParam("workspaceId") UUID workspaceId, SiteResource.SiteRequest request) {
        Site site = sites.create(
                workspaceId,
                request.name(),
                request.timezone(),
                request.defaultLanguage(),
                request.rawRetentionDays(),
                request.aggregateRetentionDays());
        return Response.status(Response.Status.CREATED)
                .entity(SiteResource.dto(site))
                .build();
    }
}
