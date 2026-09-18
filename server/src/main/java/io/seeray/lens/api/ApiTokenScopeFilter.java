package io.seeray.lens.api;

import io.quarkus.security.identity.SecurityIdentity;
import io.seeray.lens.application.ApiTokenAuthenticator;
import jakarta.annotation.Priority;
import jakarta.inject.Inject;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import java.util.Map;
import java.util.UUID;

/** Limits API tokens to site-scoped APIs and their own workspace's read-only discovery endpoints. */
@Provider
@Priority(Priorities.AUTHORIZATION + 100)
public class ApiTokenScopeFilter implements ContainerRequestFilter {
    @Inject
    SecurityIdentity identity;

    @Override
    public void filter(ContainerRequestContext request) {
        if (!ApiTokenAuthenticator.TYPE.equals(identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_TYPE))) return;

        String[] path = request.getUriInfo().getPath().replaceFirst("^/+", "").split("/");
        String method = request.getMethod();
        boolean canRead = Boolean.TRUE.equals(identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_CAN_READ));
        boolean canWrite = Boolean.TRUE.equals(identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_CAN_WRITE));

        if (isSiteApi(path)) {
            if (isReadMethod(method) && canRead || canWrite) return;
            reject(request, 403, "API_TOKEN_SCOPE_REQUIRED", "This API token does not allow this site operation");
            return;
        }

        if (path.length == 3
                && "api".equals(path[0])
                && "v1".equals(path[1])
                && "workspaces".equals(path[2])
                && "GET".equals(method)
                && canRead) return;

        if (isWorkspaceApi(path)) {
            UUID boundWorkspace = identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_WORKSPACE_ID);
            if (!boundWorkspace.toString().equals(path[3])) {
                reject(request, 404, "WORKSPACE_NOT_FOUND", "Workspace not found");
                return;
            }
            boolean discoveryRead = "GET".equals(method)
                    && (path.length == 3
                            || path.length == 4
                            || path.length == 5 && "sites".equals(path[4])
                            || path.length == 6 && "analytics".equals(path[4]) && "rollup".equals(path[5]));
            if (discoveryRead && canRead) return;
        }

        reject(request, 403, "API_TOKEN_SCOPE_REQUIRED", "This API token is limited to site-scoped APIs");
    }

    private static boolean isSiteApi(String[] path) {
        if (path.length < 4 || !"api".equals(path[0]) || !"v1".equals(path[1]) || !"sites".equals(path[2]))
            return false;
        if (path.length == 3) return false;
        try {
            UUID.fromString(path[3]);
            return true;
        } catch (IllegalArgumentException ignored) {
            return false;
        }
    }

    private static boolean isWorkspaceApi(String[] path) {
        if (path.length < 4 || !"api".equals(path[0]) || !"v1".equals(path[1]) || !"workspaces".equals(path[2]))
            return false;
        try {
            UUID.fromString(path[3]);
            return true;
        } catch (IllegalArgumentException ignored) {
            return false;
        }
    }

    private static boolean isReadMethod(String method) {
        return "GET".equals(method) || "HEAD".equals(method) || "OPTIONS".equals(method);
    }

    private static void reject(ContainerRequestContext request, int status, String code, String message) {
        request.abortWith(Response.status(status)
                .type(MediaType.APPLICATION_JSON_TYPE)
                .entity(Map.of("code", code, "message", message))
                .build());
    }
}
