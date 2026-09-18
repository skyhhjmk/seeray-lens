package io.seeray.lens.api;

import io.seeray.lens.application.ExperimentService;
import io.seeray.lens.application.SiteService;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.site.SiteAllowedDomain;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.net.URI;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;

@Path("/api/v1/experiments/{trackingId}/definitions")
@Produces(MediaType.APPLICATION_JSON)
public class ExperimentPublishedResource {
    private static final Pattern VISITOR_ID =
            Pattern.compile("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$");
    private final ExperimentService experiments;
    private final SiteService sites;

    public ExperimentPublishedResource(ExperimentService experiments, SiteService sites) {
        this.experiments = experiments;
        this.sites = sites;
    }

    @GET
    public Response definitions(
            @PathParam("trackingId") String trackingId,
            @HeaderParam("Origin") String origin,
            @QueryParam("visitorId") String clientVisitorId) {
        if (origin == null || origin.isBlank())
            throw new ControlPlaneException(403, "ORIGIN_REQUIRED", "Origin is required");
        if (clientVisitorId != null && !VISITOR_ID.matcher(clientVisitorId).matches())
            throw new ControlPlaneException(400, "INVALID_VISITOR_ID", "Visitor ID must be a UUID");
        Site site = Site.find("trackingId", trackingId).firstResult();
        if (site == null) throw new ControlPlaneException(404, "TRACKING_ID_NOT_FOUND", "Tracking site was not found");
        if (!allowed(host(origin), sites.trackingDomains(site.id)))
            throw new ControlPlaneException(403, "ORIGIN_NOT_ALLOWED", "Tracking origin is not allowed");
        return Response.ok(experiments.publicDefinitions(trackingId, clientVisitorId))
                .header("Cache-Control", "private, no-store")
                .header("Vary", "Origin")
                .build();
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
