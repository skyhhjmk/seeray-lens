package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.HeatmapConfigService;
import io.seeray.lens.application.HeatmapQueryService;
import io.seeray.lens.application.HeatmapSnapshotService;
import jakarta.validation.Valid;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.StreamingOutput;
import java.io.InputStream;
import java.util.*;

@Authenticated
@Path("/api/v1/sites/{siteId}/heatmaps")
@Produces(MediaType.APPLICATION_JSON)
public class HeatmapResource {
    private final HeatmapQueryService heatmaps;
    private final HeatmapSnapshotService snapshots;
    private final HeatmapConfigService configs;

    public HeatmapResource(
            HeatmapQueryService heatmaps, HeatmapSnapshotService snapshots, HeatmapConfigService configs) {
        this.heatmaps = heatmaps;
        this.snapshots = snapshots;
        this.configs = configs;
    }

    @GET
    @Path("/config")
    public HeatmapConfigService.Config config(@PathParam("siteId") UUID siteId) {
        return configs.get(siteId);
    }

    @PUT
    @Path("/config")
    @Consumes(MediaType.APPLICATION_JSON)
    public HeatmapConfigService.Config update(
            @PathParam("siteId") UUID siteId, @Valid HeatmapConfigResource.UpdateRequest request) {
        return configs.update(
                siteId,
                new HeatmapConfigService.Update(
                        request.enabled, request.sampleRate, request.rawRetentionDays, request.aggregateRetentionDays));
    }

    @GET
    @Path("/pages")
    public List<HeatmapQueryService.Page> pages(
            @PathParam("siteId") UUID siteId,
            @DefaultValue("0") @QueryParam("offset") int offset,
            @DefaultValue("100") @QueryParam("limit") int limit) {
        return heatmaps.pages(siteId, offset, limit);
    }

    @GET
    @Path("/variants")
    public List<HeatmapQueryService.Variant> variants(
            @PathParam("siteId") UUID siteId, @QueryParam("page") String page) {
        return heatmaps.variants(siteId, page);
    }

    @GET
    @Path("/stats")
    public HeatmapQueryService.Stats stats(
            @PathParam("siteId") UUID siteId,
            @QueryParam("variantId") UUID variant,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("type") String type) {
        if (variant == null || type == null) throw new BadRequestException("variantId and type are required");
        return heatmaps.stats(siteId, variant, from, to, type);
    }

    @GET
    @Path("/snapshots")
    public List<HeatmapSnapshotService.Snapshot> snapshots(
            @PathParam("siteId") UUID siteId, @QueryParam("variantId") UUID variantId) {
        return snapshots.list(siteId, variantId);
    }

    @POST
    @Path("/snapshots")
    @Consumes({"image/png", "image/jpeg"})
    public HeatmapSnapshotService.Snapshot upload(
            @PathParam("siteId") UUID siteId,
            @QueryParam("variantId") UUID variantId,
            @HeaderParam("Content-Type") String contentType,
            InputStream body) {
        if (variantId == null) throw new BadRequestException("variantId is required");
        String type =
                contentType == null ? "" : contentType.split(";", 2)[0].trim().toLowerCase(Locale.ROOT);
        return snapshots.upload(siteId, variantId, body, type);
    }

    @GET
    @Path("/snapshots/{snapshotId}/image")
    public Response image(@PathParam("siteId") UUID siteId, @PathParam("snapshotId") UUID snapshotId) {
        HeatmapSnapshotService.FileData file = snapshots.image(siteId, snapshotId);
        StreamingOutput stream = output -> java.nio.file.Files.copy(file.file(), output);
        return Response.ok(stream, file.contentType()).build();
    }

    @GET
    @Path("/snapshots/{snapshotId}/tiles/{tile}")
    public Response tile(
            @PathParam("siteId") UUID siteId, @PathParam("snapshotId") UUID snapshotId, @PathParam("tile") int tile) {
        HeatmapSnapshotService.FileData file = snapshots.tile(siteId, snapshotId, tile);
        StreamingOutput stream = output -> java.nio.file.Files.copy(file.file(), output);
        return Response.ok(stream, file.contentType()).build();
    }

    @DELETE
    @Path("/snapshots/{snapshotId}")
    public Response delete(@PathParam("siteId") UUID siteId, @PathParam("snapshotId") UUID snapshotId) {
        snapshots.delete(siteId, snapshotId);
        return Response.noContent().build();
    }
}
