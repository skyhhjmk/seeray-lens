package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.OfflineConversionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/offline-conversions/google-ads")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class GoogleAdsOfflineConversionResource {
    private final OfflineConversionService conversions;

    public GoogleAdsOfflineConversionResource(OfflineConversionService conversions) {
        this.conversions = conversions;
    }

    @GET
    @Path("/config")
    public OfflineConversionService.GoogleAdsConfigView config(@PathParam("siteId") UUID siteId) {
        return conversions.googleAdsConfig(siteId);
    }

    @PUT
    @Path("/config")
    public OfflineConversionService.GoogleAdsConfigView saveConfig(
            @PathParam("siteId") UUID siteId, @Valid ConfigRequest request) {
        return conversions.saveGoogleAdsConfig(
                siteId,
                new OfflineConversionService.GoogleAdsConfigInput(
                        request.customerId(),
                        request.loginCustomerId(),
                        request.conversionActionId(),
                        request.currencyCode()));
    }

    @POST
    @Path("/validate")
    public OfflineConversionService.GoogleAdsTransferResult validate(
            @PathParam("siteId") UUID siteId, @Valid TransferRequest request) {
        return conversions.transferToGoogleAds(siteId, request.toInput(), true);
    }

    @POST
    @Path("/send")
    public OfflineConversionService.GoogleAdsTransferResult send(
            @PathParam("siteId") UUID siteId, @Valid TransferRequest request) {
        return conversions.transferToGoogleAds(siteId, request.toInput(), false);
    }

    public record ConfigRequest(
            @NotBlank @Size(max = 32) String customerId,
            @Size(max = 32) String loginCustomerId,
            @NotBlank @Size(max = 20) String conversionActionId,
            @NotBlank @Size(min = 3, max = 3) String currencyCode) {}

    public record TransferRequest(
            @NotNull UUID goalId,
            @NotBlank String clickIdType,
            @NotBlank String eventSource,
            @NotEmpty @Size(max = 2_000) List<@Valid TransferRow> rows) {
        OfflineConversionService.GoogleAdsTransferInput toInput() {
            return new OfflineConversionService.GoogleAdsTransferInput(
                    goalId,
                    clickIdType,
                    eventSource,
                    rows.stream()
                            .map(row -> new OfflineConversionService.RowInput(
                                    row.conversionId(), row.platform(), row.clickId(), row.convertedAt()))
                            .toList());
        }
    }

    public record TransferRow(
            @NotBlank @Size(max = 256) String conversionId,
            @NotBlank @Size(max = 32) String platform,
            @NotBlank @Size(max = 2_048) String clickId,
            @NotBlank @Size(max = 64) String convertedAt) {}
}
