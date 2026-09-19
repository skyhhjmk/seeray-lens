package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceExtensionDeliveryService;
import io.seeray.lens.application.WorkspaceExtensionService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/extensions")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceExtensionResource {
    private final WorkspaceExtensionService extensions;
    private final WorkspaceExtensionDeliveryService deliveryService;

    public WorkspaceExtensionResource(
            WorkspaceExtensionService extensions, WorkspaceExtensionDeliveryService deliveryService) {
        this.extensions = extensions;
        this.deliveryService = deliveryService;
    }

    @GET
    public List<WorkspaceExtensionService.ExtensionView> list(@PathParam("workspaceId") UUID workspaceId) {
        return extensions.list(workspaceId);
    }

    @POST
    public Response create(
            @PathParam("workspaceId") UUID workspaceId, WorkspaceExtensionService.CreateRequest request) {
        var created = extensions.create(workspaceId, request);
        return Response.status(Response.Status.CREATED).entity(created).build();
    }

    @PUT
    @Path("/{extensionId}")
    public WorkspaceExtensionService.ExtensionView update(
            @PathParam("workspaceId") UUID workspaceId,
            @PathParam("extensionId") UUID extensionId,
            WorkspaceExtensionService.UpdateRequest request) {
        return extensions.update(workspaceId, extensionId, request);
    }

    @POST
    @Path("/{extensionId}/archive")
    public WorkspaceExtensionService.ExtensionView archive(
            @PathParam("workspaceId") UUID workspaceId, @PathParam("extensionId") UUID extensionId) {
        return extensions.archive(workspaceId, extensionId);
    }

    @POST
    @Path("/{extensionId}/rotate-secret")
    public WorkspaceExtensionService.RotatedSecret rotateSecret(
            @PathParam("workspaceId") UUID workspaceId, @PathParam("extensionId") UUID extensionId) {
        return extensions.rotateSecret(workspaceId, extensionId);
    }

    @POST
    @Path("/{extensionId}/test")
    public WorkspaceExtensionService.TestResult test(
            @PathParam("workspaceId") UUID workspaceId, @PathParam("extensionId") UUID extensionId) {
        return extensions.test(workspaceId, extensionId);
    }

    @GET
    @Path("/{extensionId}/deliveries")
    public List<io.seeray.lens.application.WorkspaceExtensionDeliveryService.DeliveryView> deliveries(
            @PathParam("workspaceId") UUID workspaceId,
            @PathParam("extensionId") UUID extensionId,
            @QueryParam("limit") @DefaultValue("25") int limit) {
        return deliveryService.list(workspaceId, extensionId, limit);
    }
}
