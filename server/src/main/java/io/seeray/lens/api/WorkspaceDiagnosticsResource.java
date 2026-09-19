package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceAccess;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.site.SiteAllowedDomain;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/** Read-only, workspace-scoped checks that turn operational failures into actionable admin work. */
@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/diagnostics")
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceDiagnosticsResource {
    private final WorkspaceAccess access;

    @Inject
    EntityManager entityManager;

    @ConfigProperty(name = "seeray.app.release-version", defaultValue = "development")
    String releaseVersion;

    public WorkspaceDiagnosticsResource(WorkspaceAccess access) {
        this.access = access;
    }

    @GET
    public DiagnosticsView get(@PathParam("workspaceId") UUID workspaceId) {
        access.requireInteractiveUser();
        access.require(workspaceId, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        Instant checkedAt = Instant.now();
        List<CheckView> checks = new ArrayList<>();

        try {
            OrganizationCheck database = databaseCheck();
            checks.add(
                    new CheckView(
                            "database",
                            database.status,
                            "Database connectivity",
                            database.detail,
                            "If this is not healthy, check the database service and connection pool before investigating reports."));
        } catch (RuntimeException error) {
            checks.add(new CheckView(
                    "database",
                    "error",
                    "Database connectivity",
                    "The control plane could not complete a database query.",
                    "Check the database service, credentials, migrations, and connection pool logs."));
        }

        List<Site> sites = Site.<Site>list("organization.id = ?1 order by name", workspaceId);
        if (sites.isEmpty()) {
            checks.add(new CheckView(
                    "sites",
                    "warning",
                    "Workspace sites",
                    "No sites are configured in this workspace.",
                    "Create a site before installing the tracker or configuring reports."));
        } else {
            checks.add(new CheckView(
                    "sites",
                    "pass",
                    "Workspace sites",
                    sites.size() + " site" + (sites.size() == 1 ? "" : "s") + " are configured.",
                    null));
        }

        long enabledTracking =
                sites.stream().filter(site -> site.trackingEnabled).count();
        checks.add(new CheckView(
                "tracking",
                enabledTracking == 0 ? "warning" : "pass",
                "Tracking availability",
                enabledTracking == 0
                        ? "Tracking is disabled for every site in this workspace."
                        : enabledTracking + " of " + sites.size() + " site" + (sites.size() == 1 ? "" : "s")
                                + " have tracking enabled.",
                enabledTracking == 0 ? "Open a site and enable tracking after reviewing its consent policy." : null));

        long sitesWithoutOrigins = sites.stream()
                .filter(site -> SiteAllowedDomain.count("site.id = ?1 and enabled = true", site.id) == 0)
                .count();
        checks.add(
                new CheckView(
                        "origins",
                        sitesWithoutOrigins == 0 && !sites.isEmpty()
                                ? "pass"
                                : (sites.isEmpty() ? "warning" : "warning"),
                        "Allowed tracker origins",
                        sites.isEmpty()
                                ? "No site origins can be checked until a site exists."
                                : sitesWithoutOrigins == 0
                                        ? "Every site has at least one enabled tracker origin."
                                        : sitesWithoutOrigins + " site" + (sitesWithoutOrigins == 1 ? "" : "s")
                                                + " have no enabled tracker origin.",
                        sitesWithoutOrigins == 0 && !sites.isEmpty()
                                ? null
                                : "Open the affected site's Domains settings and add the exact HTTPS host used by the tracker."));

        long invalidRetention = sites.stream()
                .filter(site -> site.rawRetentionDays < 1
                        || site.aggregateRetentionDays < site.rawRetentionDays
                        || site.aggregateRetentionDays > 3650)
                .count();
        checks.add(new CheckView(
                "retention",
                invalidRetention == 0 ? "pass" : "error",
                "Retention policy",
                invalidRetention == 0
                        ? "All site retention policies are internally consistent."
                        : invalidRetention + " site" + (invalidRetention == 1 ? " has" : "s have")
                                + " an invalid retention policy.",
                invalidRetention == 0
                        ? null
                        : "Edit retention settings so raw data is positive and does not outlive aggregate retention."));

        checks.add(releaseCheck());
        checks.add(extensionDeliveryCheck(workspaceId));

        String overall = checks.stream().anyMatch(check -> "error".equals(check.status))
                ? "error"
                : checks.stream().anyMatch(check -> "warning".equals(check.status)) ? "warning" : "pass";
        return new DiagnosticsView(overall, checkedAt, List.copyOf(checks));
    }

    private OrganizationCheck databaseCheck() {
        long count = Site.count();
        return new OrganizationCheck(
                "pass",
                "Database query succeeded; " + count + " site" + (count == 1 ? "" : "s")
                        + " are visible to the control plane.");
    }

    private CheckView releaseCheck() {
        try {
            Number applied = (Number) entityManager
                    .createNativeQuery("select count(*) from databasechangelog")
                    .getSingleResult();
            return new CheckView(
                    "release",
                    "pass",
                    "Release and migrations",
                    "Release " + releaseVersion + " is running with " + applied.longValue() + " migrations applied.",
                    "Database migrations are applied automatically at startup; review the release notes before deploying a newer build.");
        } catch (RuntimeException error) {
            return new CheckView(
                    "release",
                    "warning",
                    "Release and migrations",
                    "The current release or migration history could not be read.",
                    "Check the deployed release configuration and database changelog before upgrading.");
        }
    }

    private CheckView extensionDeliveryCheck(UUID workspaceId) {
        try {
            Object[] counts = (Object[]) entityManager
                    .createNativeQuery("select count(*) filter (where d.status='pending'), "
                            + "count(*) filter (where d.status='failed'), "
                            + "count(*) filter (where d.status='sending') "
                            + "from workspace_extension_delivery d "
                            + "join workspace_extension e on e.id=d.extension_id "
                            + "where e.organization_id=?1")
                    .setParameter(1, workspaceId)
                    .getSingleResult();
            long pending = ((Number) counts[0]).longValue();
            long failed = ((Number) counts[1]).longValue();
            long sending = ((Number) counts[2]).longValue();
            if (failed > 0) {
                return new CheckView(
                        "extension-delivery",
                        "error",
                        "Extension delivery queue",
                        failed + (failed == 1 ? " extension delivery is" : " extension deliveries are") + " failed.",
                        "Open Workspace → Extensions → Delivery activity and retry failed deliveries after checking the endpoint.");
            }
            if (pending > 100) {
                return new CheckView(
                        "extension-delivery",
                        "warning",
                        "Extension delivery queue",
                        pending + " extension deliveries are waiting to be sent.",
                        "Check the extension endpoint health and queue worker logs before accepting more traffic.");
            }
            return new CheckView(
                    "extension-delivery",
                    "pass",
                    "Extension delivery queue",
                    pending + " waiting, " + sending + " sending, and no failed extension deliveries.",
                    null);
        } catch (RuntimeException error) {
            return new CheckView(
                    "extension-delivery",
                    "warning",
                    "Extension delivery queue",
                    "Extension delivery queue status could not be read.",
                    "Check that the extension delivery migration and database connection are healthy.");
        }
    }

    private record OrganizationCheck(String status, String detail) {}

    public record DiagnosticsView(String overallStatus, Instant checkedAt, List<CheckView> checks) {}

    public record CheckView(String key, String status, String title, String detail, String remediation) {}
}
