package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.AnalyticsQueryService;
import io.seeray.lens.application.CustomDimensionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/custom-dimensions")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class CustomDimensionResource {
    private final CustomDimensionService dimensions;
    private final AnalyticsQueryService analytics;

    public CustomDimensionResource(CustomDimensionService dimensions, AnalyticsQueryService analytics) {
        this.dimensions = dimensions;
        this.analytics = analytics;
    }

    @GET
    public List<CustomDimensionService.Definition> list(@PathParam("siteId") UUID siteId) {
        return dimensions.list(siteId);
    }

    @POST
    public CustomDimensionService.Definition create(@PathParam("siteId") UUID siteId, @Valid Request request) {
        return dimensions.create(siteId, request.update());
    }

    @PUT
    @Path("/{dimensionId}")
    public CustomDimensionService.Definition update(
            @PathParam("siteId") UUID siteId, @PathParam("dimensionId") UUID dimensionId, @Valid Request request) {
        return dimensions.update(siteId, dimensionId, request.update());
    }

    @DELETE
    @Path("/{dimensionId}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("dimensionId") UUID dimensionId) {
        dimensions.delete(siteId, dimensionId);
    }

    @GET
    @Path("/{dimensionId}/report")
    public List<CustomDimensionService.Value> report(
            @PathParam("siteId") UUID siteId,
            @PathParam("dimensionId") UUID dimensionId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId,
            @DefaultValue("50") @QueryParam("limit") int limit) {
        return dimensions.report(siteId, dimensionId, analytics.range(siteId, from, to), limit, segmentId);
    }

    public static class Request {
        @NotBlank
        @Pattern(regexp = "[a-z][a-z0-9_]{0,63}")
        public String key;

        @NotBlank
        @Size(max = 128)
        public String name;

        @Size(max = 512)
        public String description = "";

        public boolean enabled = true;

        CustomDimensionService.Update update() {
            return new CustomDimensionService.Update(key, name, description, enabled);
        }
    }
}
