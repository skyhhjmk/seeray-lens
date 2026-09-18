package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.ScheduledReportService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/scheduled-reports")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class ScheduledReportResource {
    private final ScheduledReportService reports;

    public ScheduledReportResource(ScheduledReportService reports) {
        this.reports = reports;
    }

    @GET
    public ScheduledReportService.ListResponse list(@PathParam("siteId") UUID siteId) {
        return reports.list(siteId);
    }

    @POST
    public ScheduledReportService.ReportView create(@PathParam("siteId") UUID siteId, ReportInput input) {
        return reports.create(siteId, input);
    }

    @PUT
    @Path("/{reportId}")
    public ScheduledReportService.ReportView update(
            @PathParam("siteId") UUID siteId, @PathParam("reportId") UUID reportId, ReportInput input) {
        return reports.update(siteId, reportId, input);
    }

    @DELETE
    @Path("/{reportId}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("reportId") UUID reportId) {
        reports.delete(siteId, reportId);
    }

    @POST
    @Path("/{reportId}/send-now")
    public ScheduledReportService.ReportView sendNow(
            @PathParam("siteId") UUID siteId, @PathParam("reportId") UUID reportId) {
        return reports.sendNow(siteId, reportId);
    }

    public record ReportInput(
            String name,
            String frequency,
            String weekday,
            Integer monthDay,
            String localTime,
            List<String> recipients,
            List<String> sections,
            Boolean enabled) {}
}
