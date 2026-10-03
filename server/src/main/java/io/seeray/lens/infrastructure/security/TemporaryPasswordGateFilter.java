package io.seeray.lens.infrastructure.security;

import io.quarkus.security.identity.SecurityIdentity;
import jakarta.annotation.Priority;
import jakarta.inject.Inject;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import java.io.IOException;

@Provider
@Priority(Priorities.AUTHORIZATION)
public class TemporaryPasswordGateFilter implements ContainerRequestFilter {
    private final SecurityIdentity identity;

    @Inject
    public TemporaryPasswordGateFilter(SecurityIdentity identity) {
        this.identity = identity;
    }

    @Override
    public void filter(ContainerRequestContext request) throws IOException {
        if (identity.isAnonymous()
                || !Boolean.TRUE.equals(identity.getAttribute("mustChangePassword"))) return;
        String path = request.getUriInfo().getPath();
        if (path.equals("api/v1/auth/me")
                || path.equals("api/v1/auth/change-password")
                || path.equals("api/v1/auth/logout")) return;
        request.abortWith(Response.status(Response.Status.FORBIDDEN)
                .type(MediaType.APPLICATION_JSON_TYPE)
                .entity(new ErrorBody("PASSWORD_CHANGE_REQUIRED", "Change your temporary password to continue"))
                .build());
    }

    public record ErrorBody(String code, String message) {}
}
