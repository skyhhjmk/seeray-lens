package io.seeray.lens.api;

import io.seeray.lens.application.HeatmapConfigService;
import io.seeray.lens.application.RecordingCaptureService;
import io.seeray.lens.application.SiteService;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.site.SiteAllowedDomain;
import io.seeray.lens.infrastructure.ingestion.TrackingRateLimiter;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.net.URI;
import java.util.List;
import java.util.Locale;

@Path("/api/v1/collect")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class RecordingTrackingResource {
    private final RecordingCaptureService captures;
    private final HeatmapConfigService configs;
    private final SiteService sites;
    private final TrackingRateLimiter rateLimiter;

    public RecordingTrackingResource(
            RecordingCaptureService captures,
            HeatmapConfigService configs,
            SiteService sites,
            TrackingRateLimiter rateLimiter) {
        this.captures = captures;
        this.configs = configs;
        this.sites = sites;
        this.rateLimiter = rateLimiter;
    }

    @POST
    @Path("/dom-snapshots/plan/{trackingId}")
    public RecordingCaptureService.SnapshotPlan snapshotPlan(
            @PathParam("trackingId") String trackingId,
            @HeaderParam("Origin") String origin,
            @HeaderParam("Referer") String referer,
            RecordingCaptureService.SnapshotIdentity request) {
        Site site = site(trackingId, origin, referer);
        HeatmapConfigService.Config config = configs.publicConfig(trackingId);
        if (!config.enabled() || !config.autoSnapshotEnabled()) unavailable();
        enforceRateLimit(trackingId);
        validateSnapshotIdentity(request);
        validatePageUrl(site, request.url());
        return captures.planSnapshot(site, request);
    }

    @POST
    @Path("/dom-snapshots/{trackingId}")
    public Response snapshot(
            @PathParam("trackingId") String trackingId,
            @HeaderParam("Origin") String origin,
            @HeaderParam("Referer") String referer,
            RecordingCaptureService.SnapshotUpload request) {
        Site site = site(trackingId, origin, referer);
        HeatmapConfigService.Config config = configs.publicConfig(trackingId);
        if (!config.enabled() || !config.autoSnapshotEnabled()) unavailable();
        enforceRateLimit(trackingId);
        validateSnapshot(request);
        validatePageUrl(site, request.url());
        RecordingCaptureService.DomSnapshot result = captures.captureSnapshot(site, request);
        return Response.status(result.captured() ? Response.Status.CREATED : Response.Status.OK)
                .entity(result)
                .build();
    }

    @POST
    @Path("/recordings/{trackingId}")
    public Response recording(
            @PathParam("trackingId") String trackingId,
            @HeaderParam("Origin") String origin,
            @HeaderParam("Referer") String referer,
            RecordingCaptureService.RecordingUpload request) {
        Site site = site(trackingId, origin, referer);
        HeatmapConfigService.Config config = configs.publicConfig(trackingId);
        if (!config.recordingEnabled()) unavailable();
        enforceRateLimit(trackingId);
        validateRecording(request);
        validatePageUrl(site, request.url());
        RecordingCaptureService.RecordingResult result =
                captures.captureRecording(site, config.recordingRetentionDays(), request);
        return Response.status(Response.Status.ACCEPTED).entity(result).build();
    }

    private Site site(String trackingId, String origin, String referer) {
        Site site = Site.find("trackingId", trackingId).firstResult();
        if (site == null || !site.trackingEnabled) {
            unavailable();
            return null;
        }
        String requestHost = host(origin == null || origin.isBlank() ? referer : origin);
        if (!allowed(requestHost, sites.trackingDomains(site.id)))
            throw new ControlPlaneException(403, "ORIGIN_NOT_ALLOWED", "Tracking origin is not allowed");
        return site;
    }

    private static void validateSnapshot(RecordingCaptureService.SnapshotUpload request) {
        if (request == null
                || request.instanceId() == null
                || request.url() == null
                || request.events() == null
                || request.layoutVersion() == null
                || request.layoutVersion().isBlank()
                || request.layoutVersion().length() > 128
                || request.targetId() == null
                || request.targetId().isBlank()
                || request.targetId().length() > 128
                || request.viewportWidth() < 1
                || request.viewportWidth() > 32768
                || request.viewportHeight() < 1
                || request.viewportHeight() > 32768
                || request.contentWidth() < 1
                || request.contentWidth() > 32768
                || request.contentHeight() < 1
                || request.contentHeight() > 32768)
            throw new ControlPlaneException(400, "INVALID_DOM_SNAPSHOT", "DOM snapshot metadata is invalid");
    }

    private static void validateSnapshotIdentity(RecordingCaptureService.SnapshotIdentity request) {
        if (request == null
                || request.url() == null
                || request.layoutVersion() == null
                || request.layoutVersion().isBlank()
                || request.targetId() == null
                || request.targetId().isBlank()
                || request.viewportWidth() < 1
                || request.viewportHeight() < 1
                || request.contentWidth() < 1
                || request.contentHeight() < 1)
            throw new ControlPlaneException(400, "INVALID_DOM_SNAPSHOT", "DOM snapshot metadata is invalid");
    }

    private static void validateRecording(RecordingCaptureService.RecordingUpload request) {
        if (request == null
                || request.recordingId() == null
                || request.instanceId() == null
                || request.url() == null
                || request.events() == null)
            throw new ControlPlaneException(400, "INVALID_RECORDING_CHUNK", "Recording chunk is invalid");
    }

    private void validatePageUrl(Site site, String url) {
        if (!allowed(host(url), sites.trackingDomains(site.id)))
            throw new ControlPlaneException(400, "INVALID_CAPTURE_URL", "Capture URL is not allowed");
    }

    private static void unavailable() {
        throw new ControlPlaneException(404, "CAPTURE_UNAVAILABLE", "Capture endpoint unavailable");
    }

    private void enforceRateLimit(String trackingId) {
        if (!rateLimiter.allow(trackingId))
            throw new ControlPlaneException(429, "RATE_LIMITED", "Tracking temporarily rate limited");
    }

    private static boolean allowed(String host, List<SiteAllowedDomain> domains) {
        if (host == null) return false;
        String value = host.toLowerCase(Locale.ROOT);
        return domains.stream()
                .anyMatch(domain -> domain.enabled
                        && (value.equals(domain.host) || domain.allowSubdomains && value.endsWith("." + domain.host)));
    }

    private static String host(String value) {
        try {
            return value == null || value.isBlank() ? null : URI.create(value).getHost();
        } catch (Exception ignored) {
            return null;
        }
    }
}
