package io.seeray.lens.api;

import static org.junit.jupiter.api.Assertions.*;

import java.util.UUID;
import org.junit.jupiter.api.Test;

class SiteAuditLogFilterTest {
    private final String siteId = UUID.randomUUID().toString();

    @Test
    void recordsOnlyConfigurationMutationRoutes() {
        var update = SiteAuditLogFilter.classify("PUT", "/api/v1/sites/" + siteId + "/segments/" + UUID.randomUUID());
        assertNotNull(update);
        assertEquals(siteId, update.siteId().toString());
        assertEquals("UPDATE", update.action());
        assertEquals("segments", update.resource());

        assertNull(SiteAuditLogFilter.classify("POST", "/api/v1/sites/" + siteId + "/segments/preview"));
        assertNull(SiteAuditLogFilter.classify("POST", "/api/v1/sites/" + siteId + "/analytics/custom-report/query"));
        assertNull(SiteAuditLogFilter.classify("GET", "/api/v1/sites/" + siteId + "/dashboards"));
    }

    @Test
    void identifiesPublishAndDuplicateActionsWithoutCapturingArbitraryPaths() {
        var publish = SiteAuditLogFilter.classify(
                "POST",
                "/api/v1/sites/" + siteId + "/tag-manager/containers/" + UUID.randomUUID() + "/versions/3/publish");
        assertNotNull(publish);
        assertEquals("PUBLISH", publish.action());
        assertEquals("tag-manager", publish.resource());

        var environmentPublish = SiteAuditLogFilter.classify(
                "POST",
                "/api/v1/sites/" + siteId + "/tag-manager/containers/" + UUID.randomUUID()
                        + "/versions/3/environments/staging/publish");
        assertNotNull(environmentPublish);
        assertEquals("PUBLISH", environmentPublish.action());
        assertEquals("tag-manager", environmentPublish.resource());

        var duplicate = SiteAuditLogFilter.classify(
                "POST", "/api/v1/sites/" + siteId + "/dashboards/" + UUID.randomUUID() + "/duplicate");
        assertNotNull(duplicate);
        assertEquals("DUPLICATE", duplicate.action());

        assertNull(SiteAuditLogFilter.classify("POST", "/api/v1/collect"));
        assertNull(SiteAuditLogFilter.classify("POST", "/api/v1/sites/not-a-uuid/dashboards"));
    }

    @Test
    void auditsReportConfigurationAndImmediateDelivery() {
        var create = SiteAuditLogFilter.classify("POST", "/api/v1/sites/" + siteId + "/scheduled-reports");
        assertNotNull(create);
        assertEquals("CREATE", create.action());
        assertEquals("scheduled-reports", create.resource());

        var update = SiteAuditLogFilter.classify(
                "PUT", "/api/v1/sites/" + siteId + "/scheduled-reports/" + UUID.randomUUID());
        assertNotNull(update);
        assertEquals("UPDATE", update.action());

        var delivery = SiteAuditLogFilter.classify(
                "POST", "/api/v1/sites/" + siteId + "/scheduled-reports/" + UUID.randomUUID() + "/send-now");
        assertNotNull(delivery);
        assertEquals("SEND_NOW", delivery.action());
    }

    @Test
    void auditsAnalyticsAlertConfigurationChanges() {
        var create = SiteAuditLogFilter.classify("POST", "/api/v1/sites/" + siteId + "/analytics-alerts");
        assertNotNull(create);
        assertEquals("CREATE", create.action());
        assertEquals("analytics-alerts", create.resource());

        var update = SiteAuditLogFilter.classify(
                "PUT", "/api/v1/sites/" + siteId + "/analytics-alerts/" + UUID.randomUUID());
        assertNotNull(update);
        assertEquals("UPDATE", update.action());

        var delete = SiteAuditLogFilter.classify(
                "DELETE", "/api/v1/sites/" + siteId + "/analytics-alerts/" + UUID.randomUUID());
        assertNotNull(delete);
        assertEquals("DELETE", delete.action());
    }

    @Test
    void recordsDistinctTagManagerProductionApprovalActions() {
        String container = UUID.randomUUID().toString();
        String request = UUID.randomUUID().toString();
        String root = "/api/v1/sites/" + siteId + "/tag-manager/containers/" + container + "/production-requests";

        assertEquals(
                "REQUEST_PRODUCTION", SiteAuditLogFilter.classify("POST", root).action());
        assertEquals(
                "APPROVE_PRODUCTION",
                SiteAuditLogFilter.classify("POST", root + "/" + request + "/approve")
                        .action());
        assertEquals(
                "REJECT_PRODUCTION",
                SiteAuditLogFilter.classify("POST", root + "/" + request + "/reject")
                        .action());
        assertEquals(
                "CANCEL_PRODUCTION",
                SiteAuditLogFilter.classify("POST", root + "/" + request + "/cancel")
                        .action());
    }

    @Test
    void classifiesOfflineConversionImportsWithoutAuditingReportReads() {
        String importPath = "/api/v1/sites/" + siteId + "/offline-conversions/imports";
        var imported = SiteAuditLogFilter.classify("POST", importPath);
        assertNotNull(imported);
        assertEquals("IMPORT", imported.action());
        assertEquals("offline-conversions", imported.resource());
        assertNull(SiteAuditLogFilter.classify("GET", importPath));
        assertNull(SiteAuditLogFilter.classify(
                "POST", "/api/v1/sites/" + siteId + "/analytics/offline-conversions/imports"));
    }

    @Test
    void auditsSearchConsolePropertyChangesButNotConnectionChecks() {
        var update = SiteAuditLogFilter.classify("PUT", "/api/v1/sites/" + siteId + "/search-console/property");
        assertNotNull(update);
        assertEquals("UPDATE", update.action());
        assertEquals("search-console", update.resource());
        assertNull(SiteAuditLogFilter.classify("POST", "/api/v1/sites/" + siteId + "/search-console/validate"));
    }

    @Test
    void auditsBingWebmasterCredentialChangesButNotConnectionChecks() {
        var update = SiteAuditLogFilter.classify("PUT", "/api/v1/sites/" + siteId + "/bing-webmaster/property");
        assertNotNull(update);
        assertEquals("UPDATE", update.action());
        assertEquals("bing-webmaster", update.resource());
        assertNull(SiteAuditLogFilter.classify("POST", "/api/v1/sites/" + siteId + "/bing-webmaster/validate"));
    }

    @Test
    void auditsYandexWebmasterCredentialChangesButNotConnectionChecks() {
        var update = SiteAuditLogFilter.classify("PUT", "/api/v1/sites/" + siteId + "/yandex-webmaster/property");
        assertNotNull(update);
        assertEquals("UPDATE", update.action());
        assertEquals("yandex-webmaster", update.resource());
        assertNull(SiteAuditLogFilter.classify("POST", "/api/v1/sites/" + siteId + "/yandex-webmaster/validate"));
    }
}
