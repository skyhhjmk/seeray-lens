package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.OfflineConversionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/offline-conversions/x-ads")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class XAdsOfflineConversionResource {
    private final OfflineConversionService conversions;

    public XAdsOfflineConversionResource(OfflineConversionService conversions) {
        this.conversions = conversions;
    }

    @GET
    @Path("/config")
    public OfflineConversionService.XAdsConfigView config(@PathParam("siteId") UUID siteId) {
        return conversions.xAdsConfig(siteId);
    }

    @PUT
    @Path("/config")
    public OfflineConversionService.XAdsConfigView saveConfig(
            @PathParam("siteId") UUID siteId, @Valid ConfigRequest request) {
        return conversions.saveXAdsConfig(
                siteId,
                new OfflineConversionService.XAdsConfigInput(
                        request.pixelId(), request.currencyCode(), request.accessToken()));
    }

    @DELETE
    @Path("/config")
    public OfflineConversionService.XAdsConfigView removeConfig(@PathParam("siteId") UUID siteId) {
        return conversions.removeXAdsConfig(siteId);
    }

    @PUT
    @Path("/config/goals/{goalId}")
    public OfflineConversionService.XAdsConfigView mapGoal(
            @PathParam("siteId") UUID siteId, @PathParam("goalId") UUID goalId, @Valid GoalMappingRequest request) {
        return conversions.mapXAdsGoal(siteId, goalId, request.eventId());
    }

    @DELETE
    @Path("/config/goals/{goalId}")
    public OfflineConversionService.XAdsConfigView removeGoalMapping(
            @PathParam("siteId") UUID siteId, @PathParam("goalId") UUID goalId) {
        return conversions.removeXAdsGoalMapping(siteId, goalId);
    }

    @POST
    @Path("/send")
    public OfflineConversionService.XAdsTransferResult send(
            @PathParam("siteId") UUID siteId, @Valid TransferRequest request) {
        return conversions.transferToXAds(
                siteId,
                new OfflineConversionService.XAdsTransferInput(
                        request.goalId(),
                        request.consentConfirmed(),
                        request.rows().stream()
                                .map(row -> new OfflineConversionService.RowInput(
                                        row.conversionId(), row.platform(), row.clickId(), row.convertedAt()))
                                .toList()));
    }

    public record ConfigRequest(
            @NotBlank @Size(max = 256) String pixelId,
            @NotBlank @Size(min = 3, max = 3) String currencyCode,
            @Size(max = 8_192) String accessToken) {}

    public record GoalMappingRequest(@NotBlank @Size(max = 256) String eventId) {}

    public record TransferRequest(
            @NotNull UUID goalId,
            boolean consentConfirmed,
            @NotEmpty @Size(max = 2_000) List<@Valid TransferRow> rows) {}

    public record TransferRow(
            @NotBlank @Size(max = 256) String conversionId,
            @NotBlank @Size(max = 32) String platform,
            @NotBlank @Size(max = 2_048) String clickId,
            @NotBlank @Size(max = 64) String convertedAt) {}
}
