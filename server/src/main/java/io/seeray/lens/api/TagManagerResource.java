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

    @PUT
    @Authenticated
    @Path("/containers/{containerId}")
    @Consumes(MediaType.APPLICATION_JSON)
    public TagManagerService.ContainerView update(
            @PathParam("siteId") UUID siteId, @PathParam("containerId") UUID id, UpdateRequest request) {
        return tags.update(siteId, id, request == null ? null : request.name, request != null && request.enabled);
    }

    @DELETE
    @Authenticated
    @Path("/containers/{containerId}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("containerId") UUID id) {
        tags.delete(siteId, id);
    }

    @GET
    @Authenticated
    @Path("/templates")
    public List<TagManagerService.TemplateView> templates(@PathParam("siteId") UUID siteId) {
        return tags.templates(siteId);
    }

    @POST
    @Authenticated
    @Path("/templates")
    @Consumes(MediaType.APPLICATION_JSON)
    public TagManagerService.TemplateView createTemplate(@PathParam("siteId") UUID siteId, TemplateRequest request) {
        return tags.createTemplate(
                siteId,
                request == null ? null : request.name,
                request == null ? null : request.description,
                request == null ? null : request.tags);
    }

    @PUT
    @Authenticated
    @Path("/templates/{templateId}")
    @Consumes(MediaType.APPLICATION_JSON)
    public TagManagerService.TemplateView updateTemplate(
            @PathParam("siteId") UUID siteId, @PathParam("templateId") UUID templateId, TemplateRequest request) {
        return tags.updateTemplate(
                siteId,
                templateId,
                request == null ? null : request.name,
                request == null ? null : request.description,
                request == null ? null : request.tags);
    }

    @DELETE
    @Authenticated
    @Path("/templates/{templateId}")
    public void deleteTemplate(@PathParam("siteId") UUID siteId, @PathParam("templateId") UUID templateId) {
        tags.deleteTemplate(siteId, templateId);
    }

    @POST
    @Authenticated
    @Path("/containers/{containerId}/preview-sessions")
    @Consumes(MediaType.APPLICATION_JSON)
    public TagManagerService.PreviewCreated createPreviewSession(
            @PathParam("siteId") UUID siteId, @PathParam("containerId") UUID containerId, PreviewRequest request) {
        return tags.createPreviewSession(
                siteId,
                containerId,
                request == null ? null : request.tags,
                request != null && request.executeCustomCode);
    }

    @GET
    @Authenticated
    @Path("/containers/{containerId}/preview-sessions/{sessionId}/events")
    public List<TagManagerService.PreviewEventView> previewEvents(
            @PathParam("siteId") UUID siteId,
            @PathParam("containerId") UUID containerId,
            @PathParam("sessionId") UUID sessionId) {
        return tags.previewEvents(siteId, containerId, sessionId);
    }

    @DELETE
    @Authenticated
    @Path("/containers/{containerId}/preview-sessions/{sessionId}")
    public void stopPreviewSession(
            @PathParam("siteId") UUID siteId,
            @PathParam("containerId") UUID containerId,
            @PathParam("sessionId") UUID sessionId) {
        tags.stopPreviewSession(siteId, containerId, sessionId);
    }

    @GET
    @Authenticated
    @Path("/containers/{containerId}/versions")
    public List<TagManagerService.VersionView> versions(
            @PathParam("siteId") UUID siteId, @PathParam("containerId") UUID id) {
        return tags.versions(siteId, id);
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

    @POST
    @Authenticated
    @Path("/containers/{containerId}/versions/{version}/environments/{environment}/publish")
    public TagManagerService.VersionView publishToEnvironment(
            @PathParam("siteId") UUID siteId,
            @PathParam("containerId") UUID id,
            @PathParam("version") int version,
            @PathParam("environment") String environment) {
        return tags.publishToEnvironment(siteId, id, version, environment);
    }

    public static class CreateRequest {
        public String name;
    }

    public static class UpdateRequest {
        public String name;
        public boolean enabled = true;
    }

    public static class TemplateRequest {
        public String name;
        public String description;
        public JsonNode tags;
    }

    public static class PreviewRequest {
        public JsonNode tags;
        public boolean executeCustomCode;
    }
}
