package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.SearchConsoleService;
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
@Path("/api/v1/sites/{siteId}/search-console")
@Produces(MediaType.APPLICATION_JSON)
public class SearchConsoleResource {
    private final SearchConsoleService searchConsole;

    public SearchConsoleResource(SearchConsoleService searchConsole) {
        this.searchConsole = searchConsole;
    }

    @GET
    @Path("/property")
    public SearchConsoleService.PropertyView property(@PathParam("siteId") UUID siteId) {
        return searchConsole.property(siteId);
    }

    @PUT
    @Path("/property")
    @Consumes(MediaType.APPLICATION_JSON)
    public SearchConsoleService.PropertyView saveProperty(
            @PathParam("siteId") UUID siteId, @Valid PropertyInput input) {
        return searchConsole.saveProperty(siteId, input.propertyUrl());
    }

    @DELETE
    @Path("/property")
    public void deleteProperty(@PathParam("siteId") UUID siteId) {
        searchConsole.deleteProperty(siteId);
    }

    @POST
    @Path("/validate")
    public SearchConsoleService.ValidationResult validate(@PathParam("siteId") UUID siteId) {
        return searchConsole.validate(siteId);
    }

    @GET
    @Path("/report")
    public SearchConsoleService.SearchConsoleReport report(
            @PathParam("siteId") UUID siteId,
            @QueryParam("from") String from,
            @QueryParam("to") String to,
            @QueryParam("dimension") String dimension) {
        return searchConsole.report(siteId, from, to, dimension);
    }

    public record PropertyInput(@NotBlank @Size(max = 2048) String propertyUrl) {}
}
