package io.seeray.lens.api;

import io.seeray.lens.application.HeatmapConfigService;
import io.seeray.lens.application.SiteService;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.site.SiteAllowedDomain;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.net.URI;
import java.util.List;
import java.util.Locale;

@Path("/api/v1")
@Produces(MediaType.APPLICATION_JSON)
public class HeatmapConfigResource {
    private final HeatmapConfigService configs;
    private final SiteService sites;

    public HeatmapConfigResource(HeatmapConfigService configs, SiteService sites) {
        this.configs = configs;
        this.sites = sites;
    }

    @GET
    @Path("/heatmap-config/{trackingId}")
    public HeatmapConfigService.Config publicConfig(
            @PathParam("trackingId") String trackingId,
            @HeaderParam("Origin") String origin,
            @HeaderParam("Referer") String referer) {
        Site site = Site.find("trackingId", trackingId).firstResult();
        if (site == null) return configs.publicConfig(trackingId);
        String host = host(origin == null || origin.isBlank() ? referer : origin);
        if (!allowed(host, sites.trackingDomains(site.id)))
            throw new ControlPlaneException(403, "ORIGIN_NOT_ALLOWED", "Tracking origin is not allowed");
        return configs.publicConfig(trackingId);
    }

    public static class UpdateRequest {
        public boolean enabled;

        @Min(0)
        @Max(100)
        public int sampleRate = 10;

        @Min(1)
        @Max(3650)
        public int rawRetentionDays = 30;

        @Min(30)
        @Max(3650)
        public int aggregateRetentionDays = 180;
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
}
