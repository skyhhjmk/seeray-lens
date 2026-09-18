package io.seeray.lens.api;

import com.fasterxml.jackson.databind.JsonNode;
import io.quarkus.security.Authenticated;
import io.seeray.lens.application.CrashSourceMapService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/crash-source-maps")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class CrashSourceMapResource {
    private final CrashSourceMapService sourceMaps;

    public CrashSourceMapResource(CrashSourceMapService sourceMaps) {
        this.sourceMaps = sourceMaps;
    }

    @GET
    public CrashSourceMapService.SourceMapListDto list(@PathParam("siteId") UUID siteId) {
        return sourceMaps.list(siteId);
    }

    @PUT
    public CrashSourceMapService.SourceMapDto upload(
            @PathParam("siteId") UUID siteId, @Valid UploadSourceMapRequest request) {
        return sourceMaps.upload(siteId, request.releaseId(), request.bundlePath(), request.sourceMap());
    }

    @DELETE
    @Path("/{mapId}")
    public Response delete(@PathParam("siteId") UUID siteId, @PathParam("mapId") UUID mapId) {
        sourceMaps.delete(siteId, mapId);
        return Response.noContent().build();
    }

    public record UploadSourceMapRequest(@NotBlank String releaseId, @NotBlank String bundlePath, JsonNode sourceMap) {}
}
