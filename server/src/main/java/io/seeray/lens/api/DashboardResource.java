package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.DashboardService;
import jakarta.validation.Valid;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/dashboards")
@Produces(MediaType.APPLICATION_JSON)
public class DashboardResource {
    private final DashboardService dashboards;

    public DashboardResource(DashboardService dashboards) {
        this.dashboards = dashboards;
    }

    @GET
    public List<DashboardService.View> list(@PathParam("siteId") UUID siteId) {
        return dashboards.list(siteId);
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public DashboardService.View create(@PathParam("siteId") UUID siteId, @Valid DashboardRequest request) {
        return dashboards.create(siteId, request.draft());
    }

    @PUT
    @Path("/{dashboardId}")
    @Consumes(MediaType.APPLICATION_JSON)
    public DashboardService.View update(
            @PathParam("siteId") UUID siteId,
            @PathParam("dashboardId") UUID dashboardId,
            @Valid DashboardRequest request) {
        return dashboards.update(siteId, dashboardId, request.draft());
    }

    @POST
    @Path("/{dashboardId}/duplicate")
    public DashboardService.View duplicate(
            @PathParam("siteId") UUID siteId, @PathParam("dashboardId") UUID dashboardId) {
        return dashboards.duplicate(siteId, dashboardId);
    }

    @DELETE
    @Path("/{dashboardId}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("dashboardId") UUID dashboardId) {
        dashboards.delete(siteId, dashboardId);
    }

    public static class DashboardRequest {
        public String name;
        public List<DashboardService.Widget> widgets;
        public boolean isDefault;

        DashboardService.Draft draft() {
            return new DashboardService.Draft(name, widgets, isDefault);
        }
    }
}
