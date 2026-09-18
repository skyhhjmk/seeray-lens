package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceRollupService;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/analytics")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceAnalyticsResource {
    private final WorkspaceRollupService rollups;

    public WorkspaceAnalyticsResource(WorkspaceRollupService rollups) {
        this.rollups = rollups;
    }

    @POST
    @Path("/rollup")
    public WorkspaceRollupService.RollupReport rollup(
            @PathParam("workspaceId") UUID workspaceId, RollupRequest request) {
        if (request == null) throw new IllegalArgumentException("Request body is required");
        return rollups.report(workspaceId, request.siteIds(), request.from(), request.to());
    }

    public record RollupRequest(List<UUID> siteIds, String from, String to) {}
}
