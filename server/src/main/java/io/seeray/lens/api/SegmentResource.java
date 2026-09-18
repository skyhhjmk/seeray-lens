package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.AnalyticsQueryService;
import io.seeray.lens.application.SegmentService;
import jakarta.validation.Valid;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/segments")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class SegmentResource {
    private final SegmentService segments;
    private final AnalyticsQueryService analytics;

    public SegmentResource(SegmentService segments, AnalyticsQueryService analytics) {
        this.segments = segments;
        this.analytics = analytics;
    }

    @GET
    public List<SegmentService.View> list(@PathParam("siteId") UUID siteId) {
        return segments.list(siteId);
    }

    @POST
    public SegmentService.View create(@PathParam("siteId") UUID siteId, @Valid Request request) {
        return segments.create(siteId, request.update());
    }

    @PUT
    @Path("/{segmentId}")
    public SegmentService.View update(
            @PathParam("siteId") UUID siteId, @PathParam("segmentId") UUID segmentId, @Valid Request request) {
        return segments.update(siteId, segmentId, request.update());
    }

    @DELETE
    @Path("/{segmentId}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("segmentId") UUID segmentId) {
        segments.delete(siteId, segmentId);
    }

    @POST
    @Path("/preview")
    public SegmentService.Preview preview(
            @PathParam("siteId") UUID siteId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @Valid Request request) {
        return segments.preview(siteId, request.update(), analytics.range(siteId, from, to));
    }

    @GET
    @Path("/{segmentId}/preview")
    public SegmentService.Preview previewSaved(
            @PathParam("siteId") UUID siteId,
            @PathParam("segmentId") UUID segmentId,
            @QueryParam("from") String from,
            @QueryParam("to") String to) {
        return segments.preview(siteId, segmentId, analytics.range(siteId, from, to));
    }

    public static class Request {
        public String name;
        public String description;
        public String matchMode;
        public List<SegmentService.Rule> rules;
        public boolean enabled = true;

        SegmentService.Update update() {
            return new SegmentService.Update(name, description, matchMode, rules, enabled);
        }
    }
}
