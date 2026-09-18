package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.AnalyticsQueryService;
import io.seeray.lens.application.CampaignCostService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/analytics/campaign-costs")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class CampaignCostResource {
    private final AnalyticsQueryService analytics;
    private final CampaignCostService costs;

    public CampaignCostResource(AnalyticsQueryService analytics, CampaignCostService costs) {
        this.analytics = analytics;
        this.costs = costs;
    }

    @GET
    public CampaignCostService.Report report(
            @PathParam("siteId") UUID siteId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("segmentId") UUID segmentId,
            @QueryParam("goalId") UUID goalId,
            @QueryParam("model") @DefaultValue("last_touch") String model,
            @QueryParam("lookbackDays") @DefaultValue("30") int lookbackDays) {
        return costs.report(siteId, analytics.range(siteId, from, to), segmentId, goalId, model, lookbackDays);
    }

    @GET
    @Path("/imports")
    public CampaignCostService.ImportHistory imports(@PathParam("siteId") UUID siteId) {
        return costs.imports(siteId);
    }

    @POST
    @Path("/imports")
    public CampaignCostService.ImportResult importRows(@PathParam("siteId") UUID siteId, @Valid ImportRequest request) {
        return costs.importRows(
                siteId,
                request.fileName(),
                request.rows().stream()
                        .map(row -> new CampaignCostService.RowInput(
                                row.date(),
                                row.platform(),
                                row.source(),
                                row.medium(),
                                row.campaign(),
                                row.currency(),
                                row.cost(),
                                row.clicks(),
                                row.impressions()))
                        .toList());
    }

    public record ImportRequest(
            @NotBlank @Size(max = 255) String fileName, @NotEmpty @Size(max = 5000) List<@Valid ImportRow> rows) {}

    public record ImportRow(
            @NotBlank @Size(max = 10) String date,
            @NotBlank @Size(max = 32) String platform,
            @NotBlank @Size(max = 128) String source,
            @NotBlank @Size(max = 128) String medium,
            @NotBlank @Size(max = 256) String campaign,
            @NotBlank @Size(max = 3) String currency,
            @NotNull @DecimalMin("0") BigDecimal cost,
            @NotNull @Min(0) @Max(1_000_000_000_000L) Long clicks,
            @NotNull @Min(0) @Max(1_000_000_000_000L) Long impressions) {}
}
