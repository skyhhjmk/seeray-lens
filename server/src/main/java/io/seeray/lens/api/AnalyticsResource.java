package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.AnalyticsQueryService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.*;

@Authenticated
@Path("/api/v1/sites/{siteId}/analytics")
@Produces(MediaType.APPLICATION_JSON)
public class AnalyticsResource {
    private final AnalyticsQueryService analytics;

    public AnalyticsResource(AnalyticsQueryService analytics) {
        this.analytics = analytics;
    }

    @GET
    @Path("/overview")
    public AnalyticsQueryService.Overview overview(
            @PathParam("siteId") UUID site, @QueryParam("from") String from, @QueryParam("to") String to) {
        var range = analytics.range(site, from, to);
        return analytics.overview(site, range);
    }

    @GET
    @Path("/timeseries")
    public List<AnalyticsQueryService.Daily> timeseries(
            @PathParam("siteId") UUID site, @QueryParam("from") String from, @QueryParam("to") String to) {
        var range = analytics.range(site, from, to);
        return analytics.timeseries(site, range);
    }

    @GET
    @Path("/pages")
    public List<AnalyticsQueryService.Page> pages(
            @PathParam("siteId") UUID site, @QueryParam("from") String from, @QueryParam("to") String to) {
        var range = analytics.range(site, from, to);
        return analytics.pages(site, range);
    }

    @GET
    @Path("/traffic")
    public List<AnalyticsQueryService.Traffic> traffic(
            @PathParam("siteId") UUID site, @QueryParam("from") String from, @QueryParam("to") String to) {
        var range = analytics.range(site, from, to);
        return analytics.traffic(site, range);
    }

    @GET
    @Path("/events")
    public List<AnalyticsQueryService.Event> events(
            @PathParam("siteId") UUID site, @QueryParam("from") String from, @QueryParam("to") String to) {
        var range = analytics.range(site, from, to);
        return analytics.events(site, range);
    }

    @GET
    @Path("/visitors")
    public AnalyticsQueryService.VisitorOverview visitors(
            @PathParam("siteId") UUID site, @QueryParam("from") String from, @QueryParam("to") String to) {
        var range = analytics.range(site, from, to);
        return analytics.visitors(site, range);
    }

    @GET
    @Path("/goals")
    public List<AnalyticsQueryService.Goal> goals(
            @PathParam("siteId") UUID site, @QueryParam("from") String from, @QueryParam("to") String to) {
        var range = analytics.range(site, from, to);
        return analytics.goals(site, range);
    }
}
