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
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import javax.sql.DataSource;

@ApplicationScoped
public class YandexWebmasterService {
    private static final int PAGE_SIZE = 500;
    private static final int MAX_QUERY_ROWS = 3_000;
    private static final String DATA_LIMIT_NOTE =
            "Yandex returns up to its top 3,000 popular queries for the selected date interval. This report is query-based; the endpoint does not provide a daily trend or page breakdown.";

    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final SecretEncryptionService encryption;
    private final YandexWebmasterGateway gateway;

    @Inject
    public YandexWebmasterService(
            DataSource dataSource,
            SiteService sites,
            WorkspaceAccess access,
            SecretEncryptionService encryption,
            YandexWebmasterGateway gateway) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
        this.encryption = encryption;
        this.gateway = gateway;
    }

    public PropertyView property(UUID siteId) {
        Site site = readableSite(siteId);
        StoredProperty property = readProperty(siteId);
        return new PropertyView(
                property != null,
                property == null ? null : property.siteUrl(),
                property == null ? null : property.updatedAt(),
                property != null,
                canManage(site));
    }

    @Transactional
    public PropertyView saveProperty(UUID siteId, String siteUrl, String oauthToken) {
        Site site = sites.site(siteId);
        access.requireInteractiveUser();
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        String normalized = normalizeSiteUrl(siteUrl);
        StoredProperty existing = readProperty(siteId);
        String token;
        if (oauthToken == null || oauthToken.isBlank()) {
            if (existing == null) {
                throw new ControlPlaneException(
                        400, "YANDEX_WEBMASTER_TOKEN_REQUIRED", "Enter a Yandex OAuth token for the first connection.");
            }
            token = encryption.decrypt(existing.oauthTokenCiphertext());
        } else {
            if (oauthToken.length() > 8_192) {
                throw new ControlPlaneException(
                        400, "YANDEX_WEBMASTER_TOKEN_INVALID", "The Yandex OAuth token is too long.");
            }
            token = oauthToken.strip();
        }
        ResolvedHost resolved = resolveVerifiedHost(token, normalized);
        byte[] encryptedToken = oauthToken == null || oauthToken.isBlank()
                ? existing.oauthTokenCiphertext()
                : encryption.encrypt(token);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "insert into yandex_webmaster_property(site_id,site_url,yandex_user_id,host_id,oauth_token_ciphertext,updated_by,updated_at) "
                                + "values(?,?,?,?,?,?,now()) on conflict(site_id) do update set site_url=excluded.site_url,"
                                + "yandex_user_id=excluded.yandex_user_id,host_id=excluded.host_id,oauth_token_ciphertext=excluded.oauth_token_ciphertext,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setString(2, normalized);
            statement.setString(3, resolved.userId());
            statement.setString(4, resolved.hostId());
            statement.setBytes(5, encryptedToken);
            statement.setObject(6, access.userId());
            statement.executeUpdate();
        } catch (Exception error) {
            throw new IllegalStateException("Could not save Yandex Webmaster property", error);
        }
        return property(siteId);
    }

    @Transactional
    public void deleteProperty(UUID siteId) {
        Site site = sites.site(siteId);
        access.requireInteractiveUser();
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement("delete from yandex_webmaster_property where site_id=?")) {
            statement.setObject(1, siteId);
            statement.executeUpdate();
        } catch (Exception error) {
            throw new IllegalStateException("Could not remove Yandex Webmaster property", error);
        }
    }

    public ValidationResult validate(UUID siteId) {
        Site site = sites.site(siteId);
        access.requireInteractiveUser();
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        StoredProperty property = requiredProperty(siteId);
        ResolvedHost resolved = resolveHost(encryption.decrypt(property.oauthTokenCiphertext()), property.siteUrl());
        if (resolved == null) {
            return new ValidationResult(
                    false,
                    false,
                    property.siteUrl(),
                    "The authorized Yandex account does not list this exact site URL. Select a verified site owned by this account.");
        }
        return new ValidationResult(
                true,
                resolved.verified(),
                property.siteUrl(),
                resolved.verified()
                        ? "Yandex Webmaster site access verified."
                        : "The Yandex account lists this site, but its ownership is not verified.");
    }

    public YandexWebmasterReport report(UUID siteId, String fromValue, String toValue, String deviceTypeValue) {
        readableSite(siteId);
        StoredProperty property = requiredProperty(siteId);
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        LocalDate to = parseDate(toValue, today);
        LocalDate from = parseDate(fromValue, to.minusDays(6));
        if (from.isAfter(to) || from.plusDays(365).isBefore(to) || to.isAfter(today)) {
            throw new ControlPlaneException(
                    400, "YANDEX_WEBMASTER_RANGE_INVALID", "Choose valid dates within a 366-day reporting range.");
        }
        String deviceType = deviceTypeValue == null || deviceTypeValue.isBlank()
                ? "ALL"
                : deviceTypeValue.strip().toUpperCase(Locale.ROOT);
        if (!List.of("ALL", "DESKTOP", "MOBILE_AND_TABLET", "MOBILE", "TABLET").contains(deviceType)) {
            throw new ControlPlaneException(
                    400,
                    "YANDEX_WEBMASTER_DEVICE_INVALID",
                    "Choose all devices, computers, mobile and tablet, mobile, or tablet.");
        }

        String token = encryption.decrypt(property.oauthTokenCiphertext());
        List<YandexWebmasterGateway.SearchQuery> queries = new ArrayList<>();
        int totalCount = 0;
        while (queries.size() < MAX_QUERY_ROWS) {
            int limit = Math.min(PAGE_SIZE, MAX_QUERY_ROWS - queries.size());
            YandexWebmasterGateway.QueryPage page = gateway.popularQueries(
                    token, property.userId(), property.hostId(), from, to, deviceType, queries.size(), limit);
            totalCount = Math.max(totalCount, page.totalCount());
            if (page.queries().isEmpty()) break;
            queries.addAll(page.queries().subList(0, Math.min(page.queries().size(), limit)));
            if (page.queries().size() < limit) break;
        }
        List<ReportRow> rows = queries.stream()
                .map(query -> new ReportRow(
                        query.query(),
                        query.clicks(),
                        query.impressions(),
                        ctr(query.clicks(), query.impressions()),
                        query.averagePosition()))
                .toList();
        double clicks = rows.stream().mapToDouble(ReportRow::clicks).sum();
        double impressions = rows.stream().mapToDouble(ReportRow::impressions).sum();
        double weightedPosition = rows.stream()
                .filter(row -> row.averagePosition() > 0 && row.impressions() > 0)
                .mapToDouble(row -> row.averagePosition() * row.impressions())
                .sum();
        double positionImpressions = rows.stream()
                .filter(row -> row.averagePosition() > 0)
                .mapToDouble(ReportRow::impressions)
                .sum();
        return new YandexWebmasterReport(
                property.siteUrl(),
                from,
                to,
                deviceType,
                clicks,
                impressions,
                ctr(clicks, impressions),
                positionImpressions == 0 ? 0 : weightedPosition / positionImpressions,
                totalCount,
                rows,
                totalCount > rows.size() || rows.size() >= MAX_QUERY_ROWS,
                DATA_LIMIT_NOTE);
    }

    static String normalizeSiteUrl(String value) {
        if (value == null || value.isBlank() || value.length() > 2_048) {
            throw new ControlPlaneException(
                    400, "YANDEX_WEBMASTER_SITE_URL_INVALID", "Enter a Yandex Webmaster site URL.");
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
                    "YANDEX_WEBMASTER_SITE_URL_INVALID",
                    "Use the exact http(s) site URL shown by Yandex Webmaster without credentials, query, or fragment.");
        }
    }

    private ResolvedHost resolveVerifiedHost(String token, String siteUrl) {
        ResolvedHost resolved = resolveHost(token, siteUrl);
        if (resolved == null) {
            throw new ControlPlaneException(
                    422,
                    "YANDEX_WEBMASTER_SITE_NOT_FOUND",
                    "The authorized Yandex account does not list this exact site URL. Choose a verified property from that account.");
        }
        if (!resolved.verified()) {
            throw new ControlPlaneException(
                    422,
                    "YANDEX_WEBMASTER_SITE_NOT_VERIFIED",
                    "Verify ownership of this site in Yandex Webmaster before saving it.");
        }
        return resolved;
    }

    private ResolvedHost resolveHost(String token, String siteUrl) {
        YandexWebmasterGateway.User user = gateway.user(token);
        return gateway.hosts(token, user.userId()).stream()
                .filter(host -> siteUrl.equals(host.siteUrl()))
                .findFirst()
                .map(host -> new ResolvedHost(user.userId(), host.hostId(), host.verified()))
                .orElse(null);
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
                    409, "YANDEX_WEBMASTER_PROPERTY_NOT_CONFIGURED", "Configure a Yandex Webmaster site first.");
        }
        return property;
    }

    private StoredProperty readProperty(UUID siteId) {
        try (var connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select site_url,yandex_user_id,host_id,oauth_token_ciphertext,updated_at from yandex_webmaster_property where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet result = statement.executeQuery()) {
                return result.next()
                        ? new StoredProperty(
                                result.getString(1),
                                result.getString(2),
                                result.getString(3),
                                result.getBytes(4),
                                result.getTimestamp(5).toInstant())
                        : null;
            }
        } catch (Exception error) {
            throw new IllegalStateException("Could not load Yandex Webmaster property", error);
        }
    }

    private static LocalDate parseDate(String value, LocalDate fallback) {
        if (value == null || value.isBlank()) return fallback;
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException error) {
            throw new ControlPlaneException(400, "YANDEX_WEBMASTER_RANGE_INVALID", "Dates must use YYYY-MM-DD format.");
        }
    }

    private static double ctr(double clicks, double impressions) {
        return impressions <= 0 ? 0 : clicks / impressions;
    }

    private record ResolvedHost(String userId, String hostId, boolean verified) {}

    private record StoredProperty(
            String siteUrl, String userId, String hostId, byte[] oauthTokenCiphertext, Instant updatedAt) {}

    public record PropertyView(
            boolean configured, String siteUrl, Instant updatedAt, boolean credentialConfigured, boolean canManage) {}

    public record ValidationResult(boolean accessible, boolean verified, String siteUrl, String message) {}

    public record ReportRow(String query, double clicks, double impressions, double ctr, double averagePosition) {}

    public record YandexWebmasterReport(
            String siteUrl,
            LocalDate from,
            LocalDate to,
            String deviceType,
            double clicks,
            double impressions,
            double ctr,
            double averagePosition,
            int totalQueries,
            List<ReportRow> rows,
            boolean mayBeTruncated,
            String dataLimitNote) {}
}
