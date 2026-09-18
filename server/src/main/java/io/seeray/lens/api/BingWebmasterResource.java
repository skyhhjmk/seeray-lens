package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.BingWebmasterService;
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
@Path("/api/v1/sites/{siteId}/bing-webmaster")
@Produces(MediaType.APPLICATION_JSON)
public class BingWebmasterResource {
    private final BingWebmasterService bingWebmaster;

    public BingWebmasterResource(BingWebmasterService bingWebmaster) {
        this.bingWebmaster = bingWebmaster;
    }

    @GET
    @Path("/property")
    public BingWebmasterService.PropertyView property(@PathParam("siteId") UUID siteId) {
        return bingWebmaster.property(siteId);
    }

    @PUT
    @Path("/property")
    @Consumes(MediaType.APPLICATION_JSON)
    public BingWebmasterService.PropertyView saveProperty(
            @PathParam("siteId") UUID siteId, @Valid PropertyInput input) {
        return bingWebmaster.saveProperty(siteId, input.siteUrl(), input.apiKey());
    }

    @DELETE
    @Path("/property")
    public void deleteProperty(@PathParam("siteId") UUID siteId) {
        bingWebmaster.deleteProperty(siteId);
    }

    @POST
    @Path("/validate")
    public BingWebmasterService.ValidationResult validate(@PathParam("siteId") UUID siteId) {
        return bingWebmaster.validate(siteId);
    }

    @GET
    @Path("/report")
    public BingWebmasterService.BingWebmasterReport report(
            @PathParam("siteId") UUID siteId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("dimension") String dimension) {
        return bingWebmaster.report(siteId, from, to, dimension);
    }

    public record PropertyInput(@NotBlank @Size(max = 2048) String siteUrl, @Size(max = 4096) String apiKey) {}
}
