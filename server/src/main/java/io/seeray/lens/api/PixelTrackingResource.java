package io.seeray.lens.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.*;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.*;
import io.seeray.lens.infrastructure.ingestion.TrackingRateLimiter;
import io.smallrye.reactive.messaging.MutinyEmitter;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.time.Duration;
import java.time.Instant;
import java.util.*;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Message;

/** JavaScript-free, one-pixel fallback. The URL is intentionally stable and contains no mutable settings. */
@Path("/api/v1/pixel")
public class PixelTrackingResource {
    private static final byte[] GIF = Base64.getDecoder().decode("R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==");
    private static final String SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\"/>";
    private final ObjectMapper mapper;
    private final SiteService sites;
    private final MutinyEmitter<String> publisher;
    private final TrackingRateLimiter rateLimiter;

    public PixelTrackingResource(
            ObjectMapper mapper,
            SiteService sites,
            @Channel("tracking-out") MutinyEmitter<String> publisher,
            TrackingRateLimiter rateLimiter) {
        this.mapper = mapper;
        this.sites = sites;
        this.publisher = publisher;
        this.rateLimiter = rateLimiter;
    }

    @GET
    @Path("/{trackingId}.gif")
    @Produces("image/gif")
    public Response gif(
            @PathParam("trackingId") String trackingId,
            @HeaderParam("Referer") String referer,
            @Context HttpHeaders headers) {
        track(trackingId, referer, headers);
        return pixel(GIF, "image/gif", trackingId, headers);
    }

    @GET
    @Path("/{trackingId}.svg")
    @Produces("image/svg+xml")
    public Response svg(
            @PathParam("trackingId") String trackingId,
            @HeaderParam("Referer") String referer,
            @Context HttpHeaders headers) {
        track(trackingId, referer, headers);
        return pixel(SVG, "image/svg+xml", trackingId, headers);
    }

    private void track(String trackingId, String referer, HttpHeaders headers) {
        try {
            if (!rateLimiter.allow(trackingId)) return;
            Site site = Site.find("trackingId", trackingId).firstResult();
            if (site == null || !site.trackingEnabled || referer == null || referer.isBlank()) return;
            TrackingSanitizer.CleanUrl page = TrackingSanitizer.url(referer, mapper);
            if (!allowed(page.host(), sites.trackingDomains(site.id))) return;
            UUID visitor = cookie(headers, visitorCookie(trackingId));
            UUID session = cookie(headers, sessionCookie(trackingId));
            TrackingMessage message = new TrackingMessage(
                    1,
                    UuidV7.next(),
                    UUID.randomUUID(),
                    site.id,
                    Instant.now(),
                    Instant.now(),
                    "page_view",
                    page,
                    new TrackingSanitizer.CleanUrl(null, null, null, null, null, null, null, null, null, null, null),
                    TrackingSanitizer.json(
                            Map.of(
                                    "visitorId",
                                    visitor.toString(),
                                    "sessionId",
                                    session.toString(),
                                    "data",
                                    Map.of("fallback", "pixel")),
                            mapper),
                    null,
                    visitor.toString(),
                    session.toString());
            publisher
                    .sendMessage(Message.of(mapper.writeValueAsString(message)))
                    .await()
                    .atMost(Duration.ofSeconds(2));
        } catch (Exception ignored) {
            // Pixel tracking must remain invisible to the page; a later request can recover.
        }
    }

    private static Response pixel(Object body, String type, String trackingId, HttpHeaders headers) {
        Response.ResponseBuilder response = Response.ok(body, type).header("Cache-Control", "no-store, max-age=0");
        UUID visitor = cookie(headers, visitorCookie(trackingId));
        UUID session = cookie(headers, sessionCookie(trackingId));
        response.header(
                "Set-Cookie", visitorCookie(trackingId) + "=" + visitor + "; Max-Age=31536000; Path=/; SameSite=Lax");
        response.header(
                "Set-Cookie", sessionCookie(trackingId) + "=" + session + "; Max-Age=1800; Path=/; SameSite=Lax");
        return response.build();
    }

    private static UUID cookie(HttpHeaders headers, String name) {
        try {
            Cookie cookie = headers.getCookies().get(name);
            return cookie == null ? UUID.randomUUID() : UUID.fromString(cookie.getValue());
        } catch (Exception ignored) {
            return UUID.randomUUID();
        }
    }

    private static String visitorCookie(String trackingId) {
        return "srlv_" + trackingId.substring(0, Math.min(40, trackingId.length()));
    }

    private static String sessionCookie(String trackingId) {
        return "srls_" + trackingId.substring(0, Math.min(40, trackingId.length()));
    }

    private static boolean allowed(String host, List<SiteAllowedDomain> domains) {
        return host != null
                && domains.stream()
                        .anyMatch(d -> d.enabled
                                && (host.equalsIgnoreCase(d.host)
                                        || d.allowSubdomains
                                                && host.toLowerCase(Locale.ROOT).endsWith("." + d.host)));
    }
}
