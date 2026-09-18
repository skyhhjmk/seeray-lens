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
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.container.ResourceInfo;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.ext.Provider;
import java.io.IOException;
import java.lang.reflect.Method;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.UUID;
import javax.sql.DataSource;
import org.jboss.logging.Logger;

/** Records successful human-user write metadata without request bodies or query values. */
@Provider
@ApplicationScoped
public class WorkspaceWriteAccessLogFilter implements ContainerRequestFilter, ContainerResponseFilter {
    private static final Logger LOG = Logger.getLogger(WorkspaceWriteAccessLogFilter.class);
    private static final String SCOPE_PROPERTY = WorkspaceWriteAccessLogFilter.class.getName() + ".scope";

    @Inject
    DataSource dataSource;

    @Inject
    SecurityIdentity identity;

    @Context
    ResourceInfo resourceInfo;

    @Override
    public void filter(ContainerRequestContext request) throws IOException {
        if (!isWriteMethod(request.getMethod()) || !isHumanAuthenticatedResource(request)) return;

        String route = routeTemplate();
        if (route == null || !route.startsWith("/api/v1/") || isAuditRoute(route)) return;
        UUID actorId;
        try {
            actorId = UUID.fromString(identity.getPrincipal().getName());
        } catch (RuntimeException error) {
            return;
        }

        UUID siteId = pathId(request, "siteId");
        UUID explicitWorkspaceId = pathId(request, "workspaceId");
        if (siteId == null && explicitWorkspaceId == null) return;

        try (Connection connection = dataSource.getConnection()) {
            UUID workspaceId = explicitWorkspaceId != null
                    ? memberWorkspace(connection, explicitWorkspaceId, actorId)
                    : siteWorkspace(connection, siteId, actorId);
            if (workspaceId != null)
                request.setProperty(SCOPE_PROPERTY, new Scope(workspaceId, actorId, siteId, route));
        } catch (SQLException | IllegalArgumentException error) {
            // A best-effort audit sink must never prevent a valid write from proceeding.
            LOG.warn("Could not resolve workspace for human API write metadata", error);
        }
    }

    @Override
    public void filter(ContainerRequestContext request, ContainerResponseContext response) throws IOException {
        if (response.getStatus() < 200 || response.getStatus() >= 300) return;
        Object value = request.getProperty(SCOPE_PROPERTY);
        if (!(value instanceof Scope scope)) return;

        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into workspace_api_write_log(id,organization_id,actor_user_id,site_id,method,"
                                + "route_template,status_code) values(?,?,?,(select id from site where id=?),?,?,?)")) {
            statement.setObject(1, UuidV7.next());
            statement.setObject(2, scope.workspaceId());
            statement.setObject(3, scope.actorId());
            statement.setObject(4, scope.siteId());
            statement.setString(5, request.getMethod());
            statement.setString(6, scope.routeTemplate());
            statement.setInt(7, response.getStatus());
            statement.executeUpdate();
        } catch (SQLException | IllegalArgumentException error) {
            // Logging failure must not turn a completed user mutation into a failed response.
            LOG.warn("Could not persist human API write metadata", error);
        }
    }

    private boolean isHumanAuthenticatedResource(ContainerRequestContext request) {
        if (identity.isAnonymous()) return false;
        String authorization = request.getHeaderString("Authorization");
        if (authorization == null || !authorization.regionMatches(true, 0, "Bearer ", 0, 7)) return false;
        if (ApiTokenAuthenticator.TYPE.equals(identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_TYPE)))
            return false;
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
        Path classPath = resourceInfo.getResourceClass().getAnnotation(Path.class);
        Path methodPath = resourceInfo.getResourceMethod().getAnnotation(Path.class);
        String route = ((classPath == null ? "" : classPath.value()) + "/"
                        + (methodPath == null ? "" : methodPath.value()))
                .replaceAll("/{2,}", "/");
        if (!route.startsWith("/")) route = "/" + route;
        if (route.length() > 1 && route.endsWith("/")) route = route.substring(0, route.length() - 1);
        return route.length() <= 512 ? route : null;
    }

    private static UUID pathId(ContainerRequestContext request, String name) {
        String value = request.getUriInfo().getPathParameters().getFirst(name);
        if (value == null) return null;
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException error) {
            return null;
        }
    }

    private static UUID memberWorkspace(Connection connection, UUID workspaceId, UUID actorId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "select organization_id from organization_member where organization_id=? and user_id=?")) {
            statement.setObject(1, workspaceId);
            statement.setObject(2, actorId);
            try (ResultSet row = statement.executeQuery()) {
                return row.next() ? row.getObject(1, UUID.class) : null;
            }
        }
    }

    private static UUID siteWorkspace(Connection connection, UUID siteId, UUID actorId) throws SQLException {
        try (PreparedStatement statement =
                connection.prepareStatement("select s.organization_id from site s join organization_member m "
                        + "on m.organization_id=s.organization_id where s.id=? and m.user_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, actorId);
            try (ResultSet row = statement.executeQuery()) {
                return row.next() ? row.getObject(1, UUID.class) : null;
            }
        }
    }

    private static boolean isWriteMethod(String method) {
        return "POST".equals(method) || "PUT".equals(method) || "PATCH".equals(method) || "DELETE".equals(method);
    }

    private static boolean isAuditRoute(String route) {
        return route.endsWith("/audit-log")
                || route.endsWith("/request-history")
                || route.endsWith("/api-read-log")
                || route.endsWith("/api-write-log")
                || route.endsWith("/auth-activity");
    }

    private record Scope(UUID workspaceId, UUID actorId, UUID siteId, String routeTemplate) {}
}
