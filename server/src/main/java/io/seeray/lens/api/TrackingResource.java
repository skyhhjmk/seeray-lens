package io.seeray.lens.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.*;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.*;
import io.seeray.lens.infrastructure.ingestion.TrackingRateLimiter;
import io.smallrye.reactive.messaging.MutinyEmitter;
import io.vertx.core.http.HttpServerRequest;
import jakarta.validation.Valid;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import jakarta.ws.rs.core.Context;
import java.net.URI;
import java.time.Instant;
import java.util.*;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Message;

@Path("/api/v1/collect")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class TrackingResource {
    private final ObjectMapper mapper;
    private final SiteService sites;
    private final MutinyEmitter<String> publisher;
    private final TrackingRateLimiter rateLimiter;
    private final GeoLocationResolver geoLocationResolver;

    public TrackingResource(
            ObjectMapper mapper,
            SiteService sites,
            @Channel("tracking-out") MutinyEmitter<String> publisher,
            TrackingRateLimiter rateLimiter,
            GeoLocationResolver geoLocationResolver) {
        this.mapper = mapper;
        this.sites = sites;
        this.publisher = publisher;
        this.rateLimiter = rateLimiter;
        this.geoLocationResolver = geoLocationResolver;
    }

    @POST
    public Response collect(
            @Valid TrackingPayload request,
            @HeaderParam("Origin") String origin,
            @HeaderParam("Referer") String referer,
            @Context HttpServerRequest httpRequest) {
        if (request.schemaVersion() == null || request.schemaVersion() != 1) {
            throw new ControlPlaneException(400, "UNSUPPORTED_SCHEMA", "Tracking schema is not supported");
        }
        if (!rateLimiter.allow(request.siteId()))
            throw new ControlPlaneException(429, "RATE_LIMITED", "Tracking temporarily rate limited");
        Site site = Site.find("trackingId", request.siteId()).firstResult();
        if (site == null || !site.trackingEnabled)
            throw new ControlPlaneException(404, "TRACKING_UNAVAILABLE", "Tracking endpoint unavailable");
        List<SiteAllowedDomain> allowed = sites.trackingDomains(site.id);
        GeoLocationResolver.Location location = geoLocationResolver.resolve(httpRequest);
        for (TrackingPayload.TrackingEvent event : request.events()) {
            TrackingSanitizer.CleanUrl page = TrackingSanitizer.url(event.url(), mapper, event.title());
            TrackingSanitizer.CleanUrl ref = TrackingSanitizer.url(event.referrer(), mapper);
            String requestOrigin = origin != null && !origin.isBlank() ? origin : referer;
            if (!matchesAllowed(page == null ? null : page.host(), allowed)
                    || requestOrigin != null
                            && !requestOrigin.isBlank()
                            && !matchesAllowed(host(requestOrigin), allowed)) {
                throw new ControlPlaneException(403, "ORIGIN_NOT_ALLOWED", "Tracking origin is not allowed");
            }
            UUID clientId;
            try {
                clientId = UUID.fromString(event.eventId());
            } catch (Exception e) {
                throw new ControlPlaneException(400, "INVALID_EVENT_ID", "Event id is invalid");
            }
            TrackingMessage message = new TrackingMessage(
                    1,
                    UuidV7.next(),
                    clientId,
                    site.id,
                    Instant.now(),
                    event.occurredAt() == null ? Instant.now() : event.occurredAt(),
                    event.type(),
                    page,
                    ref,
                    TrackingSanitizer.json(eventData(event, location), mapper),
                    event.durationMs(),
                    event.visitorId(),
                    event.sessionId());
            try {
                publisher
                        .sendMessage(Message.of(mapper.writeValueAsString(message)))
                        .await()
                        .atMost(java.time.Duration.ofSeconds(5));
            } catch (Exception e) {
                throw new WebApplicationException(Response.status(503)
                        .header("Retry-After", "5")
                        .entity(Map.of("code", "INGESTION_UNAVAILABLE", "message", "Tracking temporarily unavailable"))
                        .build());
            }
        }
        return Response.status(Response.Status.ACCEPTED).build();
    }

    private static boolean matchesAllowed(String candidate, List<SiteAllowedDomain> domains) {
        if (candidate == null) return false;
        String value = candidate.toLowerCase(Locale.ROOT);
        return domains.stream()
                .anyMatch(
                        d -> d.enabled && (value.equals(d.host) || d.allowSubdomains && value.endsWith("." + d.host)));
    }

    private static String host(String value) {
        if (value == null || value.isBlank()) return null;
        try {
            return URI.create(value).getHost();
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<String, Object> eventData(
            TrackingPayload.TrackingEvent event, GeoLocationResolver.Location location) {
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("visitorId", event.visitorId() == null ? "" : event.visitorId());
        value.put("sessionId", event.sessionId() == null ? "" : event.sessionId());
        value.put("category", event.category() == null ? "" : event.category());
        value.put("action", event.action() == null ? "" : event.action());
        value.put("name", event.name() == null ? "" : event.name());
        Map<String, Object> context = event.context() == null ? new LinkedHashMap<>() : context(event.context());
        // Server-resolved location is authoritative and is only attached to page views.
        // Client context cannot forge these values because the server overwrites them.
        if ("page_view".equals(event.type()) && location != null && !location.isEmpty()) {
            context.put("countryCode", location.countryCode());
            put(context, "continentCode", location.continentCode());
            put(context, "regionCode", location.regionCode());
            put(context, "region", location.region());
            put(context, "city", location.city());
            put(context, "geoTimezone", location.timezone());
        }
        value.put("context", context);
        value.put(
                "data",
                event.data() == null && event.properties() == null
                        ? Map.of()
                        : event.data() == null ? event.properties() : event.data());
        return value;
    }

    private static Map<String, Object> context(TrackingPayload.ClientContext context) {
        Map<String, Object> value = new LinkedHashMap<>();
        put(value, "browser", context.browser());
        put(value, "browserVersion", context.browserVersion());
        put(value, "operatingSystem", context.operatingSystem());
        put(value, "operatingSystemVersion", context.operatingSystemVersion());
        put(value, "deviceType", context.deviceType());
        put(value, "language", context.language());
        put(value, "screenWidth", context.screenWidth());
        put(value, "screenHeight", context.screenHeight());
        put(value, "viewportWidth", context.viewportWidth());
        put(value, "viewportHeight", context.viewportHeight());
        put(value, "pixelRatio", context.pixelRatio());
        return value;
    }

    private static void put(Map<String, Object> values, String key, Object value) {
        if (value != null) values.put(key, value);
    }
}
