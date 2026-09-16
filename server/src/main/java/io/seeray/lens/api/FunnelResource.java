package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.AnalyticsQueryService;
import io.seeray.lens.application.FunnelService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/funnels")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class FunnelResource {
    private final FunnelService funnels;
    private final AnalyticsQueryService analytics;

    public FunnelResource(FunnelService funnels, AnalyticsQueryService analytics) {
        this.funnels = funnels;
        this.analytics = analytics;
    }

    @GET
    public List<FunnelService.View> list(@PathParam("siteId") UUID siteId) {
        return funnels.list(siteId);
    }

    @POST
    public FunnelService.View create(@PathParam("siteId") UUID siteId, @Valid Request request) {
        return funnels.create(siteId, request.update());
    }

    @PUT
    @Path("/{funnelId}")
    public FunnelService.View update(
            @PathParam("siteId") UUID siteId, @PathParam("funnelId") UUID funnelId, @Valid Request request) {
        return funnels.update(siteId, funnelId, request.update());
    }

    @DELETE
    @Path("/{funnelId}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("funnelId") UUID funnelId) {
        funnels.delete(siteId, funnelId);
    }

    @GET
    @Path("/{funnelId}/report")
    public FunnelService.Report report(
            @PathParam("siteId") UUID siteId,
            @PathParam("funnelId") UUID funnelId,
            @QueryParam("from") String from,
            @QueryParam("to") String to) {
        return funnels.report(siteId, funnelId, analytics.range(siteId, from, to));
    }

    public static class Request {
        public boolean enabled = true;

        @NotBlank
        @Size(max = 256)
        public String name;

        @NotNull
        @Size(min = 2, max = 10)
        public List<Step> steps;

        FunnelService.Update update() {
            return new FunnelService.Update(
                    enabled, name, steps.stream().map(Step::toDomain).toList());
        }
    }

    public static class Step {
        @NotBlank
        public String name;

        @NotBlank
        @Pattern(regexp = "event|page_view")
        public String type;

        public String eventType;
        public String eventName;
        public String path;
        public String matchMode = "exact";

        FunnelService.Step toDomain() {
            return new FunnelService.Step(name, type, eventType, eventName, path, matchMode);
        }
    }
}
