package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.PageOverlayService;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/analytics/page-overlay-sessions")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class PageOverlaySessionResource {
    private final PageOverlayService overlays;

    public PageOverlaySessionResource(PageOverlayService overlays) {
        this.overlays = overlays;
    }

    @POST
    public PageOverlayService.Created create(@PathParam("siteId") UUID siteId, CreateRequest request) {
        if (request == null) throw new IllegalArgumentException("Request body is required");
        return overlays.create(siteId, request.sourcePath(), request.from(), request.to(), request.segmentId());
    }

    public record CreateRequest(String sourcePath, String from, String to, UUID segmentId) {}
}
