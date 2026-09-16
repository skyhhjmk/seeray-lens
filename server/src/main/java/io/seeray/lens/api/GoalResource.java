package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.GoalService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

@Authenticated
@Path("/api/v1/sites/{siteId}/goals")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class GoalResource {
    private final GoalService goals;

    public GoalResource(GoalService goals) {
        this.goals = goals;
    }

    @GET
    public List<GoalService.View> list(@PathParam("siteId") UUID siteId) {
        return goals.list(siteId);
    }

    @POST
    public GoalService.View create(@PathParam("siteId") UUID siteId, @Valid Request request) {
        return goals.create(siteId, request.update());
    }

    @PUT
    @Path("/{goalId}")
    public GoalService.View update(
            @PathParam("siteId") UUID siteId, @PathParam("goalId") UUID goalId, @Valid Request request) {
        return goals.update(siteId, goalId, request.update());
    }

    @DELETE
    @Path("/{goalId}")
    public void delete(@PathParam("siteId") UUID siteId, @PathParam("goalId") UUID goalId) {
        goals.delete(siteId, goalId);
    }

    public static class Request {
        public boolean enabled = true;

        @NotBlank
        @Size(max = 256)
        public String name;

        @NotBlank
        @Pattern(regexp = "event|page_view")
        public String triggerType;

        @Size(max = 64)
        public String eventType;

        @Size(max = 256)
        public String eventName;

        @Size(max = 2048)
        public String pathPattern;

        @Pattern(regexp = "exact|contains")
        public String pathMatchMode = "exact";

        @NotNull
        @DecimalMin("0")
        @Digits(integer = 14, fraction = 4)
        public BigDecimal fixedValue = BigDecimal.ZERO;

        GoalService.Update update() {
            return new GoalService.Update(
                    enabled, name, triggerType, eventType, eventName, pathPattern, pathMatchMode, fixedValue);
        }
    }
}
