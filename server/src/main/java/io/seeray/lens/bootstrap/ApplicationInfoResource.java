package io.seeray.lens.bootstrap;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.Map;

/** Phase 1 bootstrap endpoint. Product APIs begin in later phases. */
@Path("/api/v1")
@Produces(MediaType.APPLICATION_JSON)
public class ApplicationInfoResource {
    @GET
    public Map<String, String> get() {
        return Map.of("name", "SeeRay Lens", "status", "bootstrap");
    }
}
