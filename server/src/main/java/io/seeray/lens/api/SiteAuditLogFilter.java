package io.seeray.lens.api;

import io.quarkus.security.identity.SecurityIdentity;
import io.seeray.lens.application.ApiTokenAuthenticator;
import io.seeray.lens.domain.common.UuidV7;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.ext.Provider;
import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.*;
import javax.sql.DataSource;
import org.jboss.logging.Logger;

/** Records successful, site-scoped configuration mutations without retaining request bodies or query values. */
@Provider
@ApplicationScoped
public class SiteAuditLogFilter implements ContainerResponseFilter {
    private static final Logger LOG = Logger.getLogger(SiteAuditLogFilter.class);
    private static final Set<String> AUDITED_RESOURCES = Set.of(
            "domains",
            "dashboards",
            "segments",
            "custom-dimensions",
            "goals",
            "experiments",
            "funnels",
            "tag-manager",
            "heatmaps",
            "scheduled-reports",
            "analytics-alerts",
            "annotations",
            "offline-conversions",
            "search-console",
            "bing-webmaster",
            "yandex-webmaster");

    @Inject
    DataSource dataSource;

    @Inject
    SecurityIdentity identity;

    @Override
    public void filter(ContainerRequestContext request, ContainerResponseContext response) throws IOException {
        if (response.getStatus() < 200 || response.getStatus() >= 300 || identity.isAnonymous()) return;
        Mutation mutation = classify(request.getMethod(), request.getUriInfo().getPath());
        if (mutation == null) return;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into site_audit_log(id,site_id,actor_user_id,actor_api_token_id,action,resource,resource_id) values(?,?,?,?,?,?,?)")) {
            statement.setObject(1, UuidV7.next());
            statement.setObject(2, mutation.siteId());
            statement.setObject(3, UUID.fromString(identity.getPrincipal().getName()));
            statement.setObject(4, identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_ID));
            statement.setString(5, mutation.action());
            statement.setString(6, mutation.resource());
            statement.setObject(7, mutation.resourceId());
            statement.executeUpdate();
        } catch (SQLException | IllegalArgumentException error) {
            // Audit persistence must not turn an otherwise successful configuration request into a failure.
            LOG.error("Could not persist site audit metadata", error);
        }
    }

    static Mutation classify(String method, String rawPath) {
        String[] path = rawPath.replaceFirst("^/+", "").split("/");
        if (path.length < 4 || !"api".equals(path[0]) || !"v1".equals(path[1]) || !"sites".equals(path[2])) return null;
        UUID siteId;
        try {
            siteId = UUID.fromString(path[3]);
        } catch (IllegalArgumentException error) {
            return null;
        }
        if ("GET".equals(method) || "OPTIONS".equals(method) || "HEAD".equals(method)) return null;
        String resource;
        int firstChild;
        if (path.length == 4) {
            resource = "site";
            firstChild = path.length;
        } else {
            resource = path[4];
            firstChild = 5;
            if (!AUDITED_RESOURCES.contains(resource)) return null;
        }
        for (int i = firstChild; i < path.length; i++) {
            if ("preview".equals(path[i]) || "report".equals(path[i]) || "validate".equals(path[i])) return null;
        }
        if ("heatmaps".equals(resource) && (path.length < 6 || !"config".equals(path[5]))) return null;
        String action =
                switch (method) {
                    case "POST" -> postAction(path, firstChild);
                    case "PUT", "PATCH" -> "UPDATE";
                    case "DELETE" -> "DELETE";
                    default -> null;
                };
        if (action == null) return null;
        UUID resourceId = null;
        for (int i = firstChild; i < path.length; i++) {
            try {
                resourceId = UUID.fromString(path[i]);
                break;
            } catch (IllegalArgumentException ignored) {
                // Route labels and action names are intentionally not stored as identifiers.
            }
        }
        return new Mutation(siteId, action, resource, resourceId);
    }

    private static String postAction(String[] path, int firstChild) {
        if (path.length <= firstChild) return "CREATE";
        String last = path[path.length - 1];
        if ("send-now".equals(last)) return "SEND_NOW";
        if ("send".equals(last) && path.length > firstChild && "google-ads".equals(path[firstChild]))
            return "SEND_TO_GOOGLE_ADS";
        if ("send".equals(last) && path.length > firstChild && "microsoft-ads".equals(path[firstChild]))
            return "SEND_TO_MICROSOFT_ADS";
        if ("send".equals(last) && path.length > firstChild && "meta-ads".equals(path[firstChild]))
            return "SEND_TO_META_ADS";
        if ("publish".equals(last)) return "PUBLISH";
        if ("duplicate".equals(last)) return "DUPLICATE";
        if ("approve".equals(last)) return "APPROVE_PRODUCTION";
        if ("reject".equals(last)) return "REJECT_PRODUCTION";
        if ("cancel".equals(last)) return "CANCEL_PRODUCTION";
        if ("production-requests".equals(last)) return "REQUEST_PRODUCTION";
        if ("imports".equals(last) && "offline-conversions".equals(path[4])) return "IMPORT";
        return "CREATE";
    }

    record Mutation(UUID siteId, String action, String resource, UUID resourceId) {}
}
