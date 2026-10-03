package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.SystemAdminService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.util.UUID;

@Authenticated
@Path("/api/v1/admin")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class SystemAdminResource {
    private final SystemAdminService admin;

    public SystemAdminResource(SystemAdminService admin) {
        this.admin = admin;
    }

    @GET
    @Path("/users")
    public SystemAdminService.Page<SystemAdminService.UserDto> users(
            @QueryParam("page") @DefaultValue("0") @Min(0) int page,
            @QueryParam("size") @DefaultValue("50") @Min(1) @Max(100) int size) {
        return admin.users(page, size);
    }

    @PATCH
    @Path("/users/{userId}")
    public SystemAdminService.UserDto updateUser(
            @PathParam("userId") UUID userId, @Valid SystemAdminService.UpdateUser request) {
        return admin.updateUser(userId, request);
    }

    @POST
    @Path("/users/{userId}/reset-password")
    public SystemAdminService.ResetPasswordResult resetPassword(@PathParam("userId") UUID userId) {
        return admin.resetPassword(userId);
    }

    @GET
    @Path("/workspaces")
    public java.util.List<SystemAdminService.WorkspaceDto> workspaces() {
        return admin.workspaces();
    }

    @GET
    @Path("/sites")
    public SystemAdminService.Page<SiteResource.SiteDto> sites(
            @QueryParam("page") @DefaultValue("0") @Min(0) int page,
            @QueryParam("size") @DefaultValue("50") @Min(1) @Max(100) int size) {
        return admin.sites(page, size);
    }

    @POST
    @Path("/sites")
    public Response createSite(@NotNull @Valid SystemAdminService.CreateSite request) {
        return Response.status(Response.Status.CREATED).entity(admin.createSite(request)).build();
    }

    @PATCH
    @Path("/sites/{siteId}")
    public SiteResource.SiteDto updateSite(
            @PathParam("siteId") UUID siteId, @Valid SystemAdminService.UpdateSite request) {
        return admin.updateSite(siteId, request);
    }

    @DELETE
    @Path("/sites/{siteId}")
    public Response deleteSite(@PathParam("siteId") UUID siteId, @Valid DeleteSiteRequest request) {
        admin.deleteSite(siteId, request == null ? null : request.confirmTrackingId());
        return Response.noContent().build();
    }

    public record DeleteSiteRequest(@NotBlank String confirmTrackingId) {}
}
