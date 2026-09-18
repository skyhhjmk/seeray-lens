package io.seeray.lens.api;

import com.fasterxml.jackson.databind.JsonNode;
import io.seeray.lens.application.SiteService;
import io.seeray.lens.application.TagManagerService;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.site.SiteAllowedDomain;
import jakarta.annotation.security.PermitAll;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.net.URI;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

@Path("/api/v1/tag-manager/{trackingId}")
@Produces(MediaType.APPLICATION_JSON)
@PermitAll
public class TagManagerPublishedResource {
    private final TagManagerService tags;
    private final SiteService sites;

    public TagManagerPublishedResource(TagManagerService tags, SiteService sites) {
        this.tags = tags;
        this.sites = sites;
    }

    @GET
    @Path("/container")
    public JsonNode published(
            @PathParam("trackingId") String trackingId,
            @HeaderParam("Origin") String origin,
            @QueryParam("environment") @DefaultValue("production") String environment) {
        requireAllowedSite(trackingId, origin);
        return tags.published(trackingId, environment);
    }

    @GET
    @Path("/preview/{sessionId}")
    public TagManagerService.PreviewBundle preview(
            @PathParam("trackingId") String trackingId,
            @PathParam("sessionId") UUID sessionId,
            @HeaderParam("Origin") String origin,
            @HeaderParam("Authorization") String authorization) {
        requireAllowedSite(trackingId, origin);
        return tags.previewBundle(trackingId, sessionId, bearerToken(authorization));
    }

    @POST
    @Path("/preview/{sessionId}/events")
    @Consumes(MediaType.APPLICATION_JSON)
    public void recordPreviewEvents(
            @PathParam("trackingId") String trackingId,
            @PathParam("sessionId") UUID sessionId,
            @HeaderParam("Origin") String origin,
            @HeaderParam("Authorization") String authorization,
            JsonNode body) {
        requireAllowedSite(trackingId, origin);
        tags.recordPreviewEvents(trackingId, sessionId, bearerToken(authorization), body);
    }

    private Site requireAllowedSite(String trackingId, String origin) {
        if (origin == null || origin.isBlank())
            throw new ControlPlaneException(403, "ORIGIN_REQUIRED", "Origin is required");
        Site site = Site.find("trackingId", trackingId).firstResult();
        if (site == null) throw new ControlPlaneException(404, "TRACKING_ID_NOT_FOUND", "Tracking site was not found");
        if (!allowed(host(origin), sites.trackingDomains(site.id)))
            throw new ControlPlaneException(403, "ORIGIN_NOT_ALLOWED", "Tracking origin is not allowed");
        return site;
    }

    private static String bearerToken(String authorization) {
        if (authorization == null || !authorization.startsWith("Bearer ")) return null;
        return authorization.substring("Bearer ".length()).trim();
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
            return URI.create(value).getHost();
        } catch (Exception ignored) {
            return null;
        }
    }
}
