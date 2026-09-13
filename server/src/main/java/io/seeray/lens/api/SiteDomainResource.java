package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.SiteService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.util.*;

@Authenticated
@Path("/api/v1/sites/{siteId}/domains")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class SiteDomainResource {
    private final SiteService sites;

    public SiteDomainResource(SiteService sites) {
        this.sites = sites;
    }

    @GET
    public List<SiteResource.DomainDto> list(@PathParam("siteId") UUID siteId) {
        return sites.domains(siteId).stream().map(SiteResource::domain).toList();
    }

    @POST
    public Response create(@PathParam("siteId") UUID siteId, SiteResource.DomainRequest request) {
        return Response.status(Response.Status.CREATED)
                .entity(SiteResource.domain(
                        sites.addDomain(siteId, request.host(), request.allowSubdomains(), request.enabled())))
                .build();
    }

    @PATCH
    @Path("/{domainId}")
    public SiteResource.DomainDto update(
            @PathParam("siteId") UUID siteId, @PathParam("domainId") UUID domainId, SiteResource.DomainPatch request) {
        return SiteResource.domain(sites.updateDomain(siteId, domainId, request.allowSubdomains(), request.enabled()));
    }

    @DELETE
    @Path("/{domainId}")
    public Response delete(@PathParam("siteId") UUID siteId, @PathParam("domainId") UUID domainId) {
        sites.deleteDomain(siteId, domainId);
        return Response.noContent().build();
    }
}
