package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.AnalyticsAlertService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/analytics-alerts")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class AnalyticsAlertResource {
    private final AnalyticsAlertService alerts;

    public AnalyticsAlertResource(AnalyticsAlertService alerts) {
        this.alerts = alerts;
    }

    @GET
    public AnalyticsAlertService.ListResponse list(@PathParam("siteId") UUID siteId) {
        return alerts.list(siteId);
    }

    @POST
    public AnalyticsAlertService.AlertView create(@PathParam("siteId") UUID siteId, AlertInput input) {
        return alerts.create(siteId, input);
    }

    @PUT
    @Path("/{alertId}")
    public AnalyticsAlertService.AlertView update(
            @PathParam("siteId") UUID siteId, @PathParam("alertId") UUID alertId, AlertInput input) {
        return alerts.update(siteId, alertId, input);
    }

    @DELETE
    @Path("/{alertId}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("alertId") UUID alertId) {
        alerts.delete(siteId, alertId);
    }

    public record AlertInput(
            String name,
            String metric,
            String direction,
            String baseline,
            Double thresholdPercent,
            String localTime,
            List<String> channels,
            List<String> recipients,
            Boolean enabled) {}
}
