package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/experiments")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class ExperimentResource {
    private final ExperimentService experiments;
    private final AnalyticsQueryService analytics;

    public ExperimentResource(ExperimentService experiments, AnalyticsQueryService analytics) {
        this.experiments = experiments;
        this.analytics = analytics;
    }

    @GET
    public List<ExperimentService.View> list(@PathParam("siteId") UUID siteId) {
        return experiments.list(siteId);
    }

    @POST
    public ExperimentService.View create(@PathParam("siteId") UUID siteId, @Valid Request r) {
        return experiments.create(siteId, r.update());
    }

    @PUT
    @Path("/{id}")
    public ExperimentService.View update(@PathParam("siteId") UUID siteId, @PathParam("id") UUID id, @Valid Request r) {
        return experiments.update(siteId, id, r.update());
    }

    @DELETE
    @Path("/{id}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("id") UUID id) {
        experiments.delete(siteId, id);
    }

    @GET
    @Path("/{id}/report")
    public ExperimentService.Report report(
            @PathParam("siteId") UUID siteId,
            @PathParam("id") UUID id,
            @QueryParam("from") String from,
            @QueryParam("to") String to) {
        return experiments.report(siteId, id, analytics.range(siteId, from, to));
    }

    public static class Request {
        public Boolean enabled;

        @Pattern(regexp = "draft|running|paused|completed|archived")
        public String status;

        @Size(max = 64)
        @Pattern(regexp = "[A-Za-z0-9][A-Za-z0-9_-]*")
        public String allocationGroup;

        @NotBlank
        @Size(max = 256)
        public String name;

        @NotNull
        @Size(min = 2, max = 10)
        public List<@NotBlank @Size(max = 120) String> variants;

        @Valid
        public TargetingRequest targeting;

        ExperimentService.Update update() {
            return new ExperimentService.Update(
                    enabled,
                    status,
                    allocationGroup,
                    name,
                    variants,
                    targeting == null ? null : targeting.update());
        }
    }

    public static class TargetingRequest {
        @Size(max = 20)
        public List<@NotBlank @Size(max = 512) String> pathPrefixes = List.of();

        @Size(max = 4)
        public List<@NotBlank @Size(max = 16) String> deviceTypes = List.of();

        public UUID segmentId;

        @Min(7)
        @Max(90)
        public int segmentLookbackDays = 30;

        ExperimentService.Targeting update() {
            return new ExperimentService.Targeting(pathPrefixes, deviceTypes, segmentId, segmentLookbackDays);
        }
    }
}
