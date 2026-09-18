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
@Path("/api/v1/sites/{siteId}/offline-conversions/imports")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class OfflineConversionResource {
    private final OfflineConversionService conversions;

    public OfflineConversionResource(OfflineConversionService conversions) {
        this.conversions = conversions;
    }

    @GET
    public OfflineConversionService.ImportHistory imports(@PathParam("siteId") UUID siteId) {
        return conversions.imports(siteId);
    }

    @POST
    public OfflineConversionService.ImportResult importRows(
            @PathParam("siteId") UUID siteId, @Valid ImportRequest request) {
        return conversions.importRows(
                siteId,
                request.goalId(),
                request.rows().stream()
                        .map(row -> new OfflineConversionService.RowInput(
                                row.conversionId(), row.platform(), row.clickId(), row.convertedAt()))
                        .toList());
    }

    public record ImportRequest(@NotNull UUID goalId, @NotEmpty @Size(max = 5000) List<@Valid ImportRow> rows) {}

    public record ImportRow(
            @NotBlank @Size(max = 256) String conversionId,
            @NotBlank @Size(max = 32) String platform,
            @NotBlank @Size(max = 2048) String clickId,
            @NotBlank @Size(max = 64) String convertedAt) {}
}
