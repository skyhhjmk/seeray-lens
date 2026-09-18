package io.seeray.lens.api;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import jakarta.annotation.security.PermitAll;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

@Path("/privacy")
@PermitAll
public class PrivacyPreferencesResource {
    private static final Pattern TRACKING_ID = Pattern.compile("^srl_[A-Za-z0-9_-]{32}$");
    private static final String CONTENT_SECURITY_POLICY =
            "default-src 'none'; script-src 'self'; style-src 'self'; frame-ancestors *; base-uri 'none'; form-action 'none'";

    @GET
    @Path("/preferences")
    @Produces(MediaType.TEXT_HTML)
    public Response preferences(@QueryParam("siteId") String trackingId) {
        if (trackingId == null || !TRACKING_ID.matcher(trackingId).matches()) {
            throw new ControlPlaneException(400, "INVALID_TRACKING_ID", "A valid tracking ID is required");
        }
        Site site = Site.find("trackingId", trackingId).firstResult();
        if (site == null || !site.trackingEnabled) {
            throw new ControlPlaneException(404, "TRACKING_UNAVAILABLE", "Privacy preferences are unavailable");
        }

        String template;
        try (InputStream input = getClass().getClassLoader().getResourceAsStream("privacy/preferences.html")) {
            if (input == null) throw new IllegalStateException("Privacy preferences template is missing");
            template = new String(input.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException exception) {
            throw new IllegalStateException("Privacy preferences could not be loaded", exception);
        }

        return Response.ok(template.replace("__SEERAY_TRACKING_ID__", trackingId))
                .type("text/html;charset=UTF-8")
                .header("Content-Security-Policy", CONTENT_SECURITY_POLICY)
                .header("Referrer-Policy", "no-referrer")
                .header("X-Content-Type-Options", "nosniff")
                .header("Cache-Control", "no-store")
                .build();
    }
}
