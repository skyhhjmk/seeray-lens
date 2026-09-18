package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.YandexWebmasterService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/yandex-webmaster")
@Produces(MediaType.APPLICATION_JSON)
public class YandexWebmasterResource {
    private final YandexWebmasterService yandexWebmaster;

    public YandexWebmasterResource(YandexWebmasterService yandexWebmaster) {
        this.yandexWebmaster = yandexWebmaster;
    }

    @GET
    @Path("/property")
    public YandexWebmasterService.PropertyView property(@PathParam("siteId") UUID siteId) {
        return yandexWebmaster.property(siteId);
    }

    @PUT
    @Path("/property")
    @Consumes(MediaType.APPLICATION_JSON)
    public YandexWebmasterService.PropertyView saveProperty(
            @PathParam("siteId") UUID siteId, @Valid PropertyInput input) {
        return yandexWebmaster.saveProperty(siteId, input.siteUrl(), input.oauthToken());
    }

    @DELETE
    @Path("/property")
    public void deleteProperty(@PathParam("siteId") UUID siteId) {
        yandexWebmaster.deleteProperty(siteId);
    }

    @POST
    @Path("/validate")
    public YandexWebmasterService.ValidationResult validate(@PathParam("siteId") UUID siteId) {
        return yandexWebmaster.validate(siteId);
    }

    @GET
    @Path("/report")
    public YandexWebmasterService.YandexWebmasterReport report(
            @PathParam("siteId") UUID siteId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("deviceType") String deviceType) {
        return yandexWebmaster.report(siteId, from, to, deviceType);
    }

    public record PropertyInput(@NotBlank @Size(max = 2048) String siteUrl, @Size(max = 8192) String oauthToken) {}
}
