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
@Path("/api/v1/sites/{siteId}/offline-conversions/linkedin-ads")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class LinkedInOfflineConversionResource {
    private final OfflineConversionService conversions;

    public LinkedInOfflineConversionResource(OfflineConversionService conversions) {
        this.conversions = conversions;
    }

    @GET
    @Path("/config")
    public OfflineConversionService.LinkedInAdsConfigView config(@PathParam("siteId") UUID siteId) {
        return conversions.linkedInAdsConfig(siteId);
    }

    @PUT
    @Path("/config")
    public OfflineConversionService.LinkedInAdsConfigView saveConfig(
            @PathParam("siteId") UUID siteId, @Valid ConfigRequest request) {
        return conversions.saveLinkedInAdsConfig(
                siteId,
                new OfflineConversionService.LinkedInAdsConfigInput(request.currencyCode(), request.apiToken()));
    }

    @DELETE
    @Path("/config")
    public OfflineConversionService.LinkedInAdsConfigView removeConfig(@PathParam("siteId") UUID siteId) {
        return conversions.removeLinkedInAdsConfig(siteId);
    }

    @PUT
    @Path("/config/goals/{goalId}")
    public OfflineConversionService.LinkedInAdsConfigView mapGoal(
            @PathParam("siteId") UUID siteId, @PathParam("goalId") UUID goalId, @Valid GoalMappingRequest request) {
        return conversions.mapLinkedInAdsGoal(siteId, goalId, request.conversionUrn());
    }

    @DELETE
    @Path("/config/goals/{goalId}")
    public OfflineConversionService.LinkedInAdsConfigView removeGoalMapping(
            @PathParam("siteId") UUID siteId, @PathParam("goalId") UUID goalId) {
        return conversions.removeLinkedInAdsGoalMapping(siteId, goalId);
    }

    @POST
    @Path("/send")
    public OfflineConversionService.LinkedInAdsTransferResult send(
            @PathParam("siteId") UUID siteId, @Valid TransferRequest request) {
        return conversions.transferToLinkedInAds(
                siteId,
                new OfflineConversionService.LinkedInAdsTransferInput(
                        request.goalId(),
                        request.consentConfirmed(),
                        request.rows().stream()
                                .map(row -> new OfflineConversionService.RowInput(
                                        row.conversionId(), row.platform(), row.clickId(), row.convertedAt()))
                                .toList()));
    }

    public record ConfigRequest(
            @NotBlank @Size(min = 3, max = 3) String currencyCode, @Size(max = 8_192) String apiToken) {}

    public record GoalMappingRequest(@NotBlank @Size(max = 128) String conversionUrn) {}

    public record TransferRequest(
            @NotNull UUID goalId,
            boolean consentConfirmed,
            @NotEmpty @Size(max = 5_000) List<@Valid TransferRow> rows) {}

    public record TransferRow(
            @NotBlank @Size(max = 256) String conversionId,
            @NotBlank @Size(max = 32) String platform,
            @NotBlank @Size(max = 2_048) String clickId,
            @NotBlank @Size(max = 64) String convertedAt) {}
}
