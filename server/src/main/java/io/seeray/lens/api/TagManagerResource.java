package io.seeray.lens.api;

import com.fasterxml.jackson.databind.JsonNode;
import io.quarkus.security.Authenticated;
import io.seeray.lens.application.TagManagerService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Path("/api/v1/sites/{siteId}/tag-manager")
@Produces(MediaType.APPLICATION_JSON)
public class TagManagerResource {
    private final TagManagerService tags;

    public TagManagerResource(TagManagerService tags) {
        this.tags = tags;
    }

    @GET
    @Authenticated
    @Path("/containers")
    public List<TagManagerService.ContainerView> list(@PathParam("siteId") UUID siteId) {
        return tags.list(siteId);
    }

    @POST
    @Authenticated
    @Path("/containers")
    @Consumes(MediaType.APPLICATION_JSON)
    public TagManagerService.ContainerView create(@PathParam("siteId") UUID siteId, CreateRequest request) {
        return tags.create(siteId, request == null ? null : request.name);
    }

    @POST
    @Authenticated
    @Path("/containers/{containerId}/versions")
    @Consumes(MediaType.APPLICATION_JSON)
    public TagManagerService.VersionView draft(
            @PathParam("siteId") UUID siteId, @PathParam("containerId") UUID id, JsonNode body) {
        return tags.draft(siteId, id, body);
    }

    @POST
    @Authenticated
    @Path("/containers/{containerId}/versions/{version}/publish")
    public TagManagerService.VersionView publish(
            @PathParam("siteId") UUID siteId, @PathParam("containerId") UUID id, @PathParam("version") int version) {
        return tags.publish(siteId, id, version);
    }

    public static class CreateRequest {
        public String name;
    }
}
