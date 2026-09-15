package io.seeray.lens.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.HeatmapConfigService;
import io.seeray.lens.application.HeatmapMessage;
import io.seeray.lens.application.HeatmapPayload;
import io.seeray.lens.application.SiteService;
import io.seeray.lens.application.TrackingSanitizer;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.site.SiteAllowedDomain;
import io.seeray.lens.infrastructure.ingestion.TrackingRateLimiter;
import io.smallrye.reactive.messaging.MutinyEmitter;
import jakarta.validation.Valid;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.net.URI;
import java.util.List;
import java.util.Locale;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Message;

@Path("/api/v1/collect/heatmaps")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class HeatmapTrackingResource {
    private static final int MAX_PAYLOAD_BYTES = 48 * 1024;
    private final SiteService sites;
    private final HeatmapConfigService configs;
    private final ObjectMapper mapper;
    private final MutinyEmitter<String> publisher;
    private final TrackingRateLimiter rateLimiter;

    public HeatmapTrackingResource(
            SiteService sites,
            HeatmapConfigService configs,
            ObjectMapper mapper,
            @Channel("heatmap-out") MutinyEmitter<String> publisher,
            TrackingRateLimiter rateLimiter) {
        this.sites = sites;
        this.configs = configs;
        this.mapper = mapper;
        this.publisher = publisher;
        this.rateLimiter = rateLimiter;
    }

    @POST
    public Response collect(
            @Valid HeatmapPayload payload,
            @HeaderParam("Origin") String origin,
            @HeaderParam("Referer") String referer,
            @HeaderParam("Content-Length") String contentLength) {
        if (oversized(contentLength, payload))
            throw new ControlPlaneException(413, "HEATMAP_PAYLOAD_TOO_LARGE", "Heatmap payload exceeds 48 KiB");
        if (payload.schemaVersion() == null || payload.schemaVersion() != 1)
            throw new ControlPlaneException(400, "UNSUPPORTED_SCHEMA", "Heatmap schema is not supported");
        if (!rateLimiter.allow(payload.siteId()))
            throw new ControlPlaneException(429, "RATE_LIMITED", "Tracking temporarily rate limited");
        Site site = Site.find("trackingId", payload.siteId()).firstResult();
        HeatmapConfigService.Config config = configs.publicConfig(payload.siteId());
        if (site == null || !site.trackingEnabled || !config.enabled())
            throw new ControlPlaneException(404, "HEATMAP_UNAVAILABLE", "Heatmap endpoint unavailable");
        List<SiteAllowedDomain> domains = sites.trackingDomains(site.id);
        String requestHost = host(origin == null || origin.isBlank() ? referer : origin);
        for (HeatmapPayload.Event event : payload.events()) {
            TrackingSanitizer.CleanUrl clean = TrackingSanitizer.url(event.url(), null);
            if (clean == null
                    || !allowed(clean.host(), domains)
                    || (requestHost != null && !allowed(requestHost, domains))
                    || ((event.type().equals("click") || event.type().equals("move"))
                            && (event.x() == null
                                    || event.y() == null
                                    || event.x() >= event.contentWidth()
                                    || event.y() >= event.contentHeight())))
                throw new ControlPlaneException(400, "INVALID_HEATMAP_EVENT", "Heatmap event is invalid");
        }
        try {
            publisher
                    .sendMessage(Message.of(
                            mapper.writeValueAsString(new HeatmapMessage(site.id, config.sampleRate(), payload))))
                    .await()
                    .atMost(java.time.Duration.ofSeconds(5));
        } catch (Exception exception) {
            throw new WebApplicationException(Response.status(503)
                    .header("Retry-After", "5")
                    .entity(java.util.Map.of(
                            "code", "INGESTION_UNAVAILABLE", "message", "Heatmap collection temporarily unavailable"))
                    .build());
        }
        return Response.status(Response.Status.ACCEPTED).build();
    }

    private static boolean allowed(String host, List<SiteAllowedDomain> domains) {
        if (host == null) return false;
        String value = host.toLowerCase(Locale.ROOT);
        return domains.stream()
                .anyMatch(
                        d -> d.enabled && (value.equals(d.host) || d.allowSubdomains && value.endsWith("." + d.host)));
    }

    private static String host(String value) {
        try {
            return value == null || value.isBlank() ? null : URI.create(value).getHost();
        } catch (Exception ignored) {
            return null;
        }
    }

    private boolean oversized(String contentLength, HeatmapPayload payload) {
        try {
            if (contentLength != null && Long.parseLong(contentLength) > MAX_PAYLOAD_BYTES) return true;
        } catch (NumberFormatException ignored) {
            // A proxy may supply an invalid or transformed Content-Length. Measure the decoded request instead.
        }
        try {
            return mapper.writeValueAsBytes(payload).length > MAX_PAYLOAD_BYTES;
        } catch (Exception failure) {
            throw new ControlPlaneException(400, "INVALID_HEATMAP_EVENT", "Heatmap event is invalid");
        }
    }
}
