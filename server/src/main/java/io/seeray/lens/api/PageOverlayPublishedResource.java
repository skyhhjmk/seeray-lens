package io.seeray.lens.api;

import io.seeray.lens.application.PageOverlayService;
import io.seeray.lens.application.SiteService;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.site.SiteAllowedDomain;
import jakarta.annotation.security.PermitAll;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.net.URI;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

@PermitAll
@Path("/api/v1/page-overlay/{trackingId}/{sessionId}")
@Produces(MediaType.APPLICATION_JSON)
public class PageOverlayPublishedResource {
    private final PageOverlayService overlays;
    private final SiteService sites;

    public PageOverlayPublishedResource(PageOverlayService overlays, SiteService sites) {
        this.overlays = overlays;
        this.sites = sites;
    }

    @GET
    public PageOverlayService.OverlayData read(
            @PathParam("trackingId") String trackingId,
            @PathParam("sessionId") UUID sessionId,
            @HeaderParam("Origin") String origin,
            @HeaderParam("Referer") String referer,
            @HeaderParam("Authorization") String authorization) {
        Site site = requireAllowedSite(trackingId, origin == null || origin.isBlank() ? referer : origin);
        String token = authorization != null && authorization.startsWith("Bearer ")
                ? authorization.substring("Bearer ".length()).trim()
                : null;
        return overlays.read(site.trackingId, sessionId, token);
    }

    private Site requireAllowedSite(String trackingId, String origin) {
        if (origin == null || origin.isBlank())
            throw new ControlPlaneException(403, "ORIGIN_REQUIRED", "Origin or Referer is required");
        Site site = Site.find("trackingId", trackingId).firstResult();
        if (site == null) throw new ControlPlaneException(404, "TRACKING_ID_NOT_FOUND", "Tracking site was not found");
        String host;
        try {
            URI uri = URI.create(origin);
            if (!"http".equalsIgnoreCase(uri.getScheme()) && !"https".equalsIgnoreCase(uri.getScheme()))
                throw new IllegalArgumentException("Origin scheme is unsupported");
            host = uri.getHost();
        } catch (Exception ignored) {
            host = null;
        }
        if (host == null || !allowed(host, sites.trackingDomains(site.id)))
            throw new ControlPlaneException(403, "ORIGIN_NOT_ALLOWED", "Tracking origin is not allowed");
        return site;
    }

    private static boolean allowed(String host, List<SiteAllowedDomain> domains) {
        String value = host.toLowerCase(Locale.ROOT);
        return domains.stream()
                .anyMatch(domain -> domain.enabled
                        && (value.equals(domain.host) || domain.allowSubdomains && value.endsWith("." + domain.host)));
    }
}
