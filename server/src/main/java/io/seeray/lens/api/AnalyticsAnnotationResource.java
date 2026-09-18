package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.AnalyticsAnnotationService;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/annotations")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class AnalyticsAnnotationResource {
    private final AnalyticsAnnotationService annotations;

    public AnalyticsAnnotationResource(AnalyticsAnnotationService annotations) {
        this.annotations = annotations;
    }

    @GET
    public AnalyticsAnnotationService.ListResponse list(
            @PathParam("siteId") UUID siteId, @QueryParam("from") String from, @QueryParam("to") String to) {
        return annotations.list(siteId, from, to);
    }

    @POST
    public Response create(@PathParam("siteId") UUID siteId, AnnotationInput input) {
        return Response.status(Response.Status.CREATED)
                .entity(annotations.create(siteId, input == null ? null : input.update()))
                .build();
    }

    @PUT
    @Path("/{annotationId}")
    public AnalyticsAnnotationService.AnnotationView update(
            @PathParam("siteId") UUID siteId, @PathParam("annotationId") UUID annotationId, AnnotationInput input) {
        return annotations.update(siteId, annotationId, input == null ? null : input.update());
    }

    @DELETE
    @Path("/{annotationId}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("annotationId") UUID annotationId) {
        annotations.delete(siteId, annotationId);
    }

    public record AnnotationInput(String date, String note) {
        AnalyticsAnnotationService.Update update() {
            return new AnalyticsAnnotationService.Update(date, note);
        }
    }
}
