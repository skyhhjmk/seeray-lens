package io.seeray.lens.api;

import com.fasterxml.jackson.databind.JsonNode;
import io.seeray.lens.application.SiteService;
import io.seeray.lens.application.TagManagerService;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.site.SiteAllowedDomain;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.net.URI;
import java.util.List;
import java.util.Locale;

@Path("/api/v1/tag-manager/{trackingId}/container")
@Produces(MediaType.APPLICATION_JSON)
public class TagManagerPublishedResource {
    private final TagManagerService tags;
    private final SiteService sites;

    public TagManagerPublishedResource(TagManagerService tags, SiteService sites) {
        this.tags = tags;
        this.sites = sites;
    }

    @GET
    public JsonNode published(@PathParam("trackingId") String trackingId, @HeaderParam("Origin") String origin) {
        if (origin == null || origin.isBlank())
            throw new ControlPlaneException(403, "ORIGIN_REQUIRED", "Origin is required");
        Site site = Site.find("trackingId", trackingId).firstResult();
        if (site == null) throw new ControlPlaneException(404, "TRACKING_ID_NOT_FOUND", "Tracking site was not found");
        if (!allowed(host(origin), sites.trackingDomains(site.id)))
            throw new ControlPlaneException(403, "ORIGIN_NOT_ALLOWED", "Tracking origin is not allowed");
        return tags.published(trackingId);
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
