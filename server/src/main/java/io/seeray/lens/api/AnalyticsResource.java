package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.AnalyticsQueryService;
import io.seeray.lens.application.AttributionQueryService;
import io.seeray.lens.application.CohortQueryService;
import io.seeray.lens.application.CustomReportService;
import io.seeray.lens.application.FormAnalyticsService;
import io.seeray.lens.application.GeoLocationResolver;
import io.seeray.lens.application.MediaAnalyticsService;
import io.seeray.lens.application.SegmentedAnalyticsQueryService;
import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.*;

@Authenticated
@Path("/api/v1/sites/{siteId}/analytics")
@Produces(MediaType.APPLICATION_JSON)
public class AnalyticsResource {
    private final AnalyticsQueryService analytics;
    private final SegmentedAnalyticsQueryService segmented;
    private final GeoLocationResolver geoLocationResolver;
    private final CustomReportService customReports;
    private final CohortQueryService cohorts;
    private final AttributionQueryService attribution;
    private final FormAnalyticsService forms;
    private final MediaAnalyticsService media;

    public AnalyticsResource(
            AnalyticsQueryService analytics,
            SegmentedAnalyticsQueryService segmented,
            GeoLocationResolver geoLocationResolver,
            CustomReportService customReports,
            CohortQueryService cohorts,
            AttributionQueryService attribution,
            FormAnalyticsService forms,
            MediaAnalyticsService media) {
        this.analytics = analytics;
        this.segmented = segmented;
        this.geoLocationResolver = geoLocationResolver;
        this.customReports = customReports;
        this.cohorts = cohorts;
        this.attribution = attribution;
        this.forms = forms;
        this.media = media;
    }

    @GET
    @Path("/overview")
    public AnalyticsQueryService.Overview overview(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        var range = analytics.range(site, from, to);
        return segmentId == null ? analytics.overview(site, range) : segmented.overview(site, range, segmentId);
    }

    @GET
    @Path("/cohorts")
    public List<CohortQueryService.RetentionCell> cohorts(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("weeks") @DefaultValue("8") int weeks,
            @QueryParam("segmentId") UUID segmentId) {
        return cohorts.report(site, analytics.range(site, from, to), segmentId, weeks);
    }

    @GET
    @Path("/timeseries")
    public List<AnalyticsQueryService.Daily> timeseries(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        var range = analytics.range(site, from, to);
        return segmentId == null ? analytics.timeseries(site, range) : segmented.timeseries(site, range, segmentId);
    }

    @GET
    @Path("/pages")
    public List<AnalyticsQueryService.Page> pages(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        var range = analytics.range(site, from, to);
        return segmentId == null ? analytics.pages(site, range) : segmented.pages(site, range, segmentId);
    }

    @GET
    @Path("/page-titles")
    public List<AnalyticsQueryService.PageTitle> pageTitles(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        var range = analytics.range(site, from, to);
        return segmentId == null ? analytics.pageTitles(site, range) : segmented.pageTitles(site, range, segmentId);
    }

    @GET
    @Path("/entry-exit")
    public List<AnalyticsQueryService.PageFlow> entryExit(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        return segmented.entryExit(site, analytics.range(site, from, to), segmentId);
    }

    @GET
    @Path("/user-flow")
    public List<AnalyticsQueryService.PageTransition> userFlow(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        return segmented.userFlow(site, analytics.range(site, from, to), segmentId);
    }

    @GET
    @Path("/user-flow/samples")
    public AnalyticsQueryService.UserFlowSamples userFlowSamples(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId,
            @QueryParam("step") Integer step,
            @QueryParam("sourcePath") String sourcePath,
            @QueryParam("sourceTitle") String sourceTitle,
            @QueryParam("targetPath") String targetPath,
            @QueryParam("targetTitle") String targetTitle,
            @QueryParam("cursor") String cursor,
            @QueryParam("exit") @DefaultValue("false") boolean exit) {
        if (step == null
                || step < 1
                || step > 5
                || sourcePath == null
                || sourcePath.isBlank()
                || sourcePath.length() > 2048
                || (!exit && (targetPath == null || targetPath.isBlank() || targetPath.length() > 2048))
                || (cursor != null && cursor.length() > 256)
                || (exit && targetPath != null)) {
            throw new ControlPlaneException(400, "INVALID_USER_FLOW_EDGE", "User-flow transition is invalid");
        }
        return segmented.userFlowSamples(
                site,
                analytics.range(site, from, to),
                segmentId,
                step,
                sourcePath,
                sourceTitle,
                exit ? null : targetPath,
                exit ? null : targetTitle,
                cursor);
    }

    @GET
    @Path("/traffic")
    public List<AnalyticsQueryService.Traffic> traffic(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        var range = analytics.range(site, from, to);
        return segmentId == null ? analytics.traffic(site, range) : segmented.traffic(site, range, segmentId);
    }

    @GET
    @Path("/events")
    public List<AnalyticsQueryService.Event> events(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        var range = analytics.range(site, from, to);
        return segmentId == null ? analytics.events(site, range) : segmented.events(site, range, segmentId);
    }

    @GET
    @Path("/site-search")
    public SegmentedAnalyticsQueryService.SiteSearchReport siteSearch(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        return segmented.siteSearch(site, analytics.range(site, from, to), segmentId);
    }

    @GET
    @Path("/content")
    public SegmentedAnalyticsQueryService.ContentReport content(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        return segmented.content(site, analytics.range(site, from, to), segmentId);
    }

    @GET
    @Path("/web-vitals")
    public SegmentedAnalyticsQueryService.WebVitalsReport webVitals(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        return segmented.webVitals(site, analytics.range(site, from, to), segmentId);
    }

    @GET
    @Path("/visitors")
    public AnalyticsQueryService.VisitorOverview visitors(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        var range = analytics.range(site, from, to);
        return segmentId == null ? analytics.visitors(site, range) : segmented.visitors(site, range, segmentId);
    }

    @GET
    @Path("/visitor-log")
    public List<AnalyticsQueryService.VisitorLog> visitorLog(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId,
            @DefaultValue("50") @QueryParam("limit") int limit) {
        var range = analytics.range(site, from, to);
        return segmentId == null
                ? analytics.visitorLog(site, range, limit)
                : segmented.visitorLog(site, range, segmentId, limit);
    }

    @GET
    @Path("/visitors/{visitorId}")
    public AnalyticsQueryService.VisitorProfile visitorProfile(
            @PathParam("siteId") UUID site,
            @PathParam("visitorId") String visitorId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        var profile = segmented.visitorProfile(site, analytics.range(site, from, to), segmentId, visitorId);
        if (profile == null) throw new NotFoundException();
        return profile;
    }

    @GET
    @Path("/visitors/{visitorId}/history")
    public AnalyticsQueryService.VisitorProfileHistoryPage visitorProfileHistory(
            @PathParam("siteId") UUID site,
            @PathParam("visitorId") String visitorId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId,
            @QueryParam("sessionsCursor") String sessionsCursor,
            @QueryParam("actionsCursor") String actionsCursor) {
        var page = segmented.visitorProfileHistory(
                site, analytics.range(site, from, to), segmentId, visitorId, sessionsCursor, actionsCursor);
        if (page == null) throw new NotFoundException();
        return page;
    }

    @GET
    @Path("/goals")
    public List<AnalyticsQueryService.Goal> goals(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        var range = analytics.range(site, from, to);
        return segmentId == null ? analytics.goals(site, range) : segmented.goals(site, range, segmentId);
    }

    @GET
    @Path("/attribution")
    public AttributionQueryService.Report attribution(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId,
            @QueryParam("goalId") UUID goalId,
            @DefaultValue("last_touch") @QueryParam("model") String model,
            @DefaultValue("30") @QueryParam("lookbackDays") int lookbackDays) {
        return attribution.report(site, analytics.range(site, from, to), segmentId, goalId, model, lookbackDays);
    }

    @GET
    @Path("/forms")
    public FormAnalyticsService.Report forms(
            @PathParam("siteId") UUID site, @QueryParam("from") String from, @QueryParam("to") String to) {
        return forms.report(site, analytics.range(site, from, to));
    }

    @GET
    @Path("/media")
    public MediaAnalyticsService.Report media(
            @PathParam("siteId") UUID site, @QueryParam("from") String from, @QueryParam("to") String to) {
        return media.report(site, analytics.range(site, from, to));
    }

    @GET
    @Path("/technology")
    public List<AnalyticsQueryService.Technology> technology(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        return segmented.technology(site, analytics.range(site, from, to), segmentId);
    }

    @GET
    @Path("/locations")
    public LocationReport locations(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        return new LocationReport(
                geoLocationResolver.configured(),
                segmented.locations(site, analytics.range(site, from, to), segmentId));
    }

    @POST
    @Path("/custom-report/query")
    @Consumes(MediaType.APPLICATION_JSON)
    public CustomReportService.Result customReport(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId,
            CustomReportService.Query request) {
        return customReports.query(site, from, to, segmentId, request);
    }

    @GET
    @Path("/custom-report/event-properties")
    public List<CustomReportService.EventProperty> customReportEventProperties(
            @PathParam("siteId") UUID site,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId) {
        return customReports.eventProperties(site, from, to, segmentId);
    }

    @GET
    @Path("/realtime")
    public List<AnalyticsQueryService.LiveVisitor> realtime(
            @PathParam("siteId") UUID site,
            @DefaultValue("30") @QueryParam("windowMinutes") int windowMinutes,
            @DefaultValue("100") @QueryParam("limit") int limit) {
        analytics.range(site, null, null); // preserves site/workspace authorization for this non-date-based report
        return analytics.realtime(site, windowMinutes, limit);
    }

    public record LocationReport(boolean sourceConfigured, List<AnalyticsQueryService.Location> rows) {}
}
