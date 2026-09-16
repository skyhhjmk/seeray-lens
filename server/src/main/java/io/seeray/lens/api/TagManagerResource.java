package io.seeray.lens.api;

import com.fasterxml.jackson.databind.JsonNode;
import io.quarkus.security.Authenticated;
import io.seeray.lens.application.TagManagerService;
import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Path("/api/v1")
@Produces(MediaType.APPLICATION_JSON)
public class TagManagerResource {
    private final TagManagerService tags;

    public TagManagerResource(TagManagerService tags) {
        this.tags = tags;
    }

    @GET
    @Authenticated
    @Path("/sites/{siteId}/tag-manager/containers")
    public List<TagManagerService.ContainerView> list(@PathParam("siteId") UUID siteId) {
        return tags.list(siteId);
    }

    @POST
    @Authenticated
    @Path("/sites/{siteId}/tag-manager/containers")
    @Consumes(MediaType.APPLICATION_JSON)
    public TagManagerService.ContainerView create(@PathParam("siteId") UUID siteId, CreateRequest request) {
        return tags.create(siteId, request == null ? null : request.name);
    }

    @POST
    @Authenticated
    @Path("/sites/{siteId}/tag-manager/containers/{containerId}/versions")
    @Consumes(MediaType.APPLICATION_JSON)
    public TagManagerService.VersionView draft(
            @PathParam("siteId") UUID siteId, @PathParam("containerId") UUID id, JsonNode body) {
        return tags.draft(siteId, id, body);
    }

    @POST
    @Authenticated
    @Path("/sites/{siteId}/tag-manager/containers/{containerId}/versions/{version}/publish")
    public TagManagerService.VersionView publish(
            @PathParam("siteId") UUID siteId, @PathParam("containerId") UUID id, @PathParam("version") int version) {
        return tags.publish(siteId, id, version);
    }

    @GET
    @Path("/tag-manager/{trackingId}/container")
    public JsonNode published(@PathParam("trackingId") String trackingId, @HeaderParam("Origin") String origin) {
        if (origin == null || origin.isBlank())
            throw new ControlPlaneException(403, "ORIGIN_REQUIRED", "Origin is required");
        return tags.published(trackingId);
    }

    public static class CreateRequest {
        public String name;
    }
}
