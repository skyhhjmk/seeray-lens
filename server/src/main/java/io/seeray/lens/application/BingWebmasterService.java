package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.net.URI;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import javax.sql.DataSource;

@ApplicationScoped
public class BingWebmasterService {
    private static final Set<String> DIMENSIONS = Set.of("query", "page", "date");
    private static final int REPORT_ROW_LIMIT = 1_000;
    private static final String DATA_LIMIT_NOTE =
            "Bing query/page reports are updated weekly and return only the provider's top rows; date, country and device breakdowns are not available from these API methods.";

    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final SecretEncryptionService encryption;
    private final BingWebmasterGateway gateway;

    @Inject
    public BingWebmasterService(
            DataSource dataSource,
            SiteService sites,
            WorkspaceAccess access,
            SecretEncryptionService encryption,
            BingWebmasterGateway gateway) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
        this.encryption = encryption;
        this.gateway = gateway;
    }

    public PropertyView property(UUID siteId) {
        Site site = readableSite(siteId);
        boolean canManage = canManage(site);
        StoredProperty property = readProperty(siteId);
        return new PropertyView(
                property != null,
                property == null ? null : property.siteUrl(),
                property == null ? null : property.updatedAt(),
                property != null,
                canManage);
    }

    @Transactional
    public PropertyView saveProperty(UUID siteId, String siteUrl, String apiKey) {
        Site site = sites.site(siteId);
        access.requireInteractiveUser();
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        String normalized = normalizeSiteUrl(siteUrl);
        StoredProperty existing = readProperty(siteId);
        byte[] encryptedKey;
        if (apiKey == null || apiKey.isBlank()) {
            if (existing == null) {
                throw new ControlPlaneException(
                        400, "BING_WEBMASTER_API_KEY_REQUIRED", "Enter a Bing Webmaster API key for the first save.");
            }
            encryptedKey = existing.apiKeyCiphertext();
        } else {
            if (apiKey.length() > 4_096) {
                throw new ControlPlaneException(400, "BING_WEBMASTER_API_KEY_INVALID", "The Bing API key is too long.");
            }
            encryptedKey = encryption.encrypt(apiKey.strip());
        }
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "insert into bing_webmaster_property(site_id,site_url,api_key_ciphertext,updated_by,updated_at) values(?,?,?,?,now()) "
                                + "on conflict(site_id) do update set site_url=excluded.site_url,api_key_ciphertext=excluded.api_key_ciphertext,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setString(2, normalized);
            statement.setBytes(3, encryptedKey);
            statement.setObject(4, access.userId());
            statement.executeUpdate();
        } catch (Exception error) {
            throw new IllegalStateException("Could not save Bing Webmaster property", error);
        }
        return property(siteId);
    }

    @Transactional
    public void deleteProperty(UUID siteId) {
        Site site = sites.site(siteId);
        access.requireInteractiveUser();
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement("delete from bing_webmaster_property where site_id=?")) {
            statement.setObject(1, siteId);
            statement.executeUpdate();
        } catch (Exception error) {
            throw new IllegalStateException("Could not remove Bing Webmaster property", error);
        }
    }

    public ValidationResult validate(UUID siteId) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        access.requireInteractiveUser();
        StoredProperty property = requiredProperty(siteId);
        List<BingWebmasterGateway.PropertyAccess> accessible =
                gateway.accessibleProperties(encryption.decrypt(property.apiKeyCiphertext()));
        BingWebmasterGateway.PropertyAccess match = accessible.stream()
                .filter(entry -> property.siteUrl().equals(entry.siteUrl()))
                .findFirst()
                .orElse(null);
        if (match == null || !match.verified()) {
            return new ValidationResult(
                    false,
                    match != null,
                    property.siteUrl(),
                    match == null
                            ? "This API key cannot access the exact Bing site URL. Use a key belonging to a user who has this site."
                            : "The site is listed for this user but is not verified in Bing Webmaster Tools.");
        }
        return new ValidationResult(true, true, property.siteUrl(), "Bing Webmaster Tools access verified.");
    }

    public BingWebmasterReport report(UUID siteId, String fromValue, String toValue, String dimensionValue) {
        readableSite(siteId);
        StoredProperty property = requiredProperty(siteId);
        String dimension = dimensionValue == null || dimensionValue.isBlank()
                ? "query"
                : dimensionValue.strip().toLowerCase(Locale.ROOT);
        if (!DIMENSIONS.contains(dimension)) {
            throw new ControlPlaneException(400, "BING_WEBMASTER_DIMENSION_INVALID", "Choose query, page, or date.");
        }
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        LocalDate to = parseDate(toValue, today.minusDays(3));
        LocalDate from = parseDate(fromValue, to.minusDays(27));
        if (from.isAfter(to) || from.isBefore(to.minusMonths(6)) || to.isAfter(today)) {
            throw new ControlPlaneException(
                    400,
                    "BING_WEBMASTER_RANGE_INVALID",
                    "Choose valid dates within Bing's last six months of available data.");
        }

        String apiKey = encryption.decrypt(property.apiKeyCiphertext());
        List<BingWebmasterGateway.TrafficStat> traffic = gateway.dailyTraffic(apiKey, property.siteUrl()).stream()
                .filter(row -> inRange(row.date(), from, to))
                .toList();
        double clicks = traffic.stream()
                .mapToDouble(BingWebmasterGateway.TrafficStat::clicks)
                .sum();
        double impressions = traffic.stream()
                .mapToDouble(BingWebmasterGateway.TrafficStat::impressions)
                .sum();
        List<ReportRow> rows;
        boolean truncated;
        if (dimension.equals("date")) {
            Map<LocalDate, Accumulator> byDate = new HashMap<>();
            for (BingWebmasterGateway.TrafficStat row : traffic) {
                byDate.computeIfAbsent(row.date(), ignored -> new Accumulator())
                        .add(row.clicks(), row.impressions(), 0);
            }
            rows = byDate.entrySet().stream()
                    .sorted(Map.Entry.comparingByKey())
                    .map(entry -> entry.getValue().toRow(entry.getKey().toString()))
                    .toList();
            truncated = false;
        } else {
            List<BingWebmasterGateway.BreakdownStat> breakdown = dimension.equals("query")
                    ? gateway.queryStats(apiKey, property.siteUrl())
                    : gateway.pageStats(apiKey, property.siteUrl());
            Map<String, Accumulator> byKey = new HashMap<>();
            breakdown.stream().filter(row -> inRange(row.date(), from, to)).forEach(row -> byKey.computeIfAbsent(
                            row.key(), ignored -> new Accumulator())
                    .add(row.clicks(), row.impressions(), row.averagePosition()));
            rows = byKey.entrySet().stream()
                    .map(entry -> entry.getValue().toRow(entry.getKey()))
                    .sorted(Comparator.comparingDouble(ReportRow::impressions)
                            .reversed()
                            .thenComparing(ReportRow::key))
                    .limit(REPORT_ROW_LIMIT)
                    .toList();
            truncated = true;
        }
        return new BingWebmasterReport(
                property.siteUrl(),
                from,
                to,
                dimension,
                clicks,
                impressions,
                ctr(clicks, impressions),
                rows,
                truncated,
                DATA_LIMIT_NOTE);
    }

    static String normalizeSiteUrl(String value) {
        if (value == null || value.isBlank() || value.length() > 2_048) {
            throw new ControlPlaneException(400, "BING_WEBMASTER_SITE_URL_INVALID", "Enter a Bing site URL.");
        }
        try {
            URI uri = URI.create(value.strip());
            if (!("http".equalsIgnoreCase(uri.getScheme()) || "https".equalsIgnoreCase(uri.getScheme()))
                    || uri.getHost() == null
                    || uri.getUserInfo() != null
                    || uri.getQuery() != null
                    || uri.getFragment() != null) {
                throw new IllegalArgumentException();
            }
            return uri.toASCIIString();
        } catch (IllegalArgumentException error) {
            throw new ControlPlaneException(
                    400,
                    "BING_WEBMASTER_SITE_URL_INVALID",
                    "Use a verified http(s) site URL without credentials, query, or fragment, for example https://www.example.com/.");
        }
    }

    private Site readableSite(UUID siteId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        return site;
    }

    private boolean canManage(Site site) {
        if (access.isApiToken()) return false;
        WorkspaceRole role = access.member(site.organization.id).role;
        return role == WorkspaceRole.OWNER || role == WorkspaceRole.ADMIN;
    }

    private StoredProperty requiredProperty(UUID siteId) {
        StoredProperty property = readProperty(siteId);
        if (property == null) {
            throw new ControlPlaneException(
                    409, "BING_WEBMASTER_PROPERTY_NOT_CONFIGURED", "Configure a Bing Webmaster site first.");
        }
        return property;
    }

    private StoredProperty readProperty(UUID siteId) {
        try (var connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select site_url,api_key_ciphertext,updated_at from bing_webmaster_property where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet result = statement.executeQuery()) {
                return result.next()
                        ? new StoredProperty(
                                result.getString(1),
                                result.getBytes(2),
                                result.getTimestamp(3).toInstant())
                        : null;
            }
        } catch (Exception error) {
            throw new IllegalStateException("Could not load Bing Webmaster property", error);
        }
    }

    private static LocalDate parseDate(String value, LocalDate fallback) {
        if (value == null || value.isBlank()) return fallback;
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException error) {
            throw new ControlPlaneException(400, "BING_WEBMASTER_RANGE_INVALID", "Dates must use YYYY-MM-DD format.");
        }
    }

    private static boolean inRange(LocalDate date, LocalDate from, LocalDate to) {
        return date != null && !date.isBefore(from) && !date.isAfter(to);
    }

    private static double ctr(double clicks, double impressions) {
        return impressions <= 0 ? 0 : clicks / impressions;
    }

    private record StoredProperty(String siteUrl, byte[] apiKeyCiphertext, Instant updatedAt) {}

    private static final class Accumulator {
        private double clicks;
        private double impressions;
        private double weightedPosition;
        private double positionedImpressions;

        void add(double clickCount, double impressionCount, double position) {
            clicks += clickCount;
            impressions += impressionCount;
            if (position > 0 && impressionCount > 0) {
                weightedPosition += position * impressionCount;
                positionedImpressions += impressionCount;
            }
        }

        ReportRow toRow(String key) {
            return new ReportRow(
                    key,
                    clicks,
                    impressions,
                    ctr(clicks, impressions),
                    positionedImpressions <= 0 ? 0 : weightedPosition / positionedImpressions);
        }
    }

    public record PropertyView(
            boolean configured, String siteUrl, Instant updatedAt, boolean credentialConfigured, boolean canManage) {}

    public record ValidationResult(boolean accessible, boolean verified, String siteUrl, String message) {}

    public record ReportRow(String key, double clicks, double impressions, double ctr, double averagePosition) {}

    public record BingWebmasterReport(
            String siteUrl,
            LocalDate from,
            LocalDate to,
            String dimension,
            double clicks,
            double impressions,
            double ctr,
            List<ReportRow> rows,
            boolean mayBeTruncated,
            String dataLimitNote) {}
}
