package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceAccess;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.site.SiteAllowedDomain;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/** Read-only, workspace-scoped checks that turn operational failures into actionable admin work. */
@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/diagnostics")
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceDiagnosticsResource {
    private final WorkspaceAccess access;

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

    private record OrganizationCheck(String status, String detail) {}

    public record DiagnosticsView(String overallStatus, Instant checkedAt, List<CheckView> checks) {}

    public record CheckView(String key, String status, String title, String detail, String remediation) {}
}
