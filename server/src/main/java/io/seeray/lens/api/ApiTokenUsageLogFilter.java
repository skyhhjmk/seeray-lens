package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.quarkus.security.identity.SecurityIdentity;
import io.seeray.lens.application.ApiTokenAuthenticator;
import io.seeray.lens.domain.common.UuidV7;
import jakarta.annotation.security.RolesAllowed;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.container.ResourceInfo;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.ext.Provider;
import java.io.IOException;
import java.lang.reflect.Method;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.UUID;
import javax.sql.DataSource;
import org.jboss.logging.Logger;

/** Records API-token request metadata only; query strings and payloads are deliberately excluded. */
@Provider
@ApplicationScoped
public class ApiTokenUsageLogFilter implements ContainerResponseFilter {
    private static final Logger LOG = Logger.getLogger(ApiTokenUsageLogFilter.class);

    @Inject
    DataSource dataSource;

    @Inject
    SecurityIdentity identity;

    @Context
    ResourceInfo resourceInfo;

    @Override
    public void filter(ContainerRequestContext request, ContainerResponseContext response) throws IOException {
        // An invalid/revoked bearer has no resolved identity; avoid resolving lazy authentication here.
        if (response.getStatus() == 401) return;
        if (!isAuthenticatedResource()) return;
        if (!ApiTokenAuthenticator.TYPE.equals(identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_TYPE))) return;
        UUID tokenId = identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_ID);
        String route = routeTemplate();
        if (tokenId == null || route == null || !route.startsWith("/api/v1/")) return;

        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into api_token_request_log(id,token_id,method,route_template,status_code) "
                                + "values(?,?,?,?,?)")) {
            statement.setObject(1, UuidV7.next());
            statement.setObject(2, tokenId);
            statement.setString(3, request.getMethod());
            statement.setString(4, route);
            statement.setInt(5, response.getStatus());
            statement.executeUpdate();
        } catch (SQLException | IllegalArgumentException error) {
            // Do not turn an otherwise completed API request into a failure if activity logging is unavailable.
            LOG.warn("Could not persist API token request metadata", error);
        }
    }

    private boolean isAuthenticatedResource() {
        if (resourceInfo == null || resourceInfo.getResourceClass() == null || resourceInfo.getResourceMethod() == null)
            return false;
        Class<?> resourceClass = resourceInfo.getResourceClass();
        Method method = resourceInfo.getResourceMethod();
        return resourceClass.isAnnotationPresent(Authenticated.class)
                || method.isAnnotationPresent(Authenticated.class)
                || resourceClass.isAnnotationPresent(RolesAllowed.class)
                || method.isAnnotationPresent(RolesAllowed.class);
    }

    private String routeTemplate() {
        if (resourceInfo == null || resourceInfo.getResourceClass() == null || resourceInfo.getResourceMethod() == null)
            return null;
        Path classPath = resourceInfo.getResourceClass().getAnnotation(Path.class);
        Method method = resourceInfo.getResourceMethod();
        Path methodPath = method.getAnnotation(Path.class);
        String route = ((classPath == null ? "" : classPath.value()) + "/"
                        + (methodPath == null ? "" : methodPath.value()))
                .replaceAll("/{2,}", "/");
        if (!route.startsWith("/")) route = "/" + route;
        return route.length() <= 512 ? route : null;
    }
}
