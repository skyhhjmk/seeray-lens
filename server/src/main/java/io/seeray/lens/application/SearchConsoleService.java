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
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import javax.sql.DataSource;

@ApplicationScoped
public class SearchConsoleService {
    private static final Set<String> DIMENSIONS = Set.of("query", "page", "country", "device", "date");
    private static final int REPORT_ROW_LIMIT = 1_000;

    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final SearchConsoleGateway gateway;

    @Inject
    public SearchConsoleService(
            DataSource dataSource, SiteService sites, WorkspaceAccess access, SearchConsoleGateway gateway) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
        this.gateway = gateway;
    }

    public PropertyView property(UUID siteId) {
        Site site = readableSite(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        StoredProperty property = readProperty(siteId);
        return new PropertyView(
                property != null,
                property == null ? null : property.propertyUrl(),
                property == null ? null : property.updatedAt(),
                property == null
                        ? "Configure a Search Console property and grant the server identity read access."
                        : "Credentials are supplied by server Google Application Default Credentials.",
                canManage);
    }

    @Transactional
    public PropertyView saveProperty(UUID siteId, String propertyUrl) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        String normalized = normalizeProperty(propertyUrl);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "insert into search_console_property(site_id,property_url,updated_by,updated_at) values(?,?,?,now()) "
                                + "on conflict(site_id) do update set property_url=excluded.property_url,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setString(2, normalized);
            statement.setObject(3, access.userId());
            statement.executeUpdate();
        } catch (Exception error) {
            throw new IllegalStateException("Could not save Search Console property", error);
        }
        return property(siteId);
    }

    @Transactional
    public void deleteProperty(UUID siteId) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement("delete from search_console_property where site_id=?")) {
            statement.setObject(1, siteId);
            statement.executeUpdate();
        } catch (Exception error) {
            throw new IllegalStateException("Could not remove Search Console property", error);
        }
    }

    public ValidationResult validate(UUID siteId) {
        Site site = readableSite(siteId);
        StoredProperty property = requiredProperty(siteId);
        List<SearchConsoleGateway.PropertyAccess> accessible = gateway.accessibleProperties();
        SearchConsoleGateway.PropertyAccess match = accessible.stream()
                .filter(entry -> property.propertyUrl().equals(entry.propertyUrl()))
                .findFirst()
                .orElse(null);
        if (match == null) {
            return new ValidationResult(
                    false,
                    property.propertyUrl(),
                    null,
                    "The server identity cannot access this exact Search Console property. Add it as a user in Search Console.");
        }
        return new ValidationResult(
                true, match.propertyUrl(), match.permissionLevel(), "Search Console access verified.");
    }

    public SearchConsoleReport report(UUID siteId, String fromValue, String toValue, String dimensionValue) {
        readableSite(siteId);
        StoredProperty property = requiredProperty(siteId);
        String dimension = dimensionValue == null || dimensionValue.isBlank()
                ? "query"
                : dimensionValue.strip().toLowerCase(Locale.ROOT);
        if (!DIMENSIONS.contains(dimension)) {
            throw new ControlPlaneException(
                    400, "SEARCH_CONSOLE_DIMENSION_INVALID", "Choose query, page, country, device, or date.");
        }
        LocalDate to = parseDate(toValue, LocalDate.now().minusDays(3));
        LocalDate from = parseDate(fromValue, to.minusDays(27));
        if (from.isAfter(to) || from.plusDays(366).isBefore(to) || to.isAfter(LocalDate.now())) {
            throw new ControlPlaneException(
                    400, "SEARCH_CONSOLE_RANGE_INVALID", "Choose valid dates within the last 367 days.");
        }
        SearchConsoleGateway.SearchResult totals = gateway.query(
                property.propertyUrl(),
                new SearchConsoleGateway.QueryRequest(from.toString(), to.toString(), List.of(), 1));
        SearchConsoleGateway.SearchResult grouped = gateway.query(
                property.propertyUrl(),
                new SearchConsoleGateway.QueryRequest(
                        from.toString(), to.toString(), List.of(dimension), REPORT_ROW_LIMIT));
        SearchConsoleGateway.SearchRow total = totals.rows().isEmpty()
                ? new SearchConsoleGateway.SearchRow(List.of(), 0, 0, 0, 0)
                : totals.rows().getFirst();
        List<SearchRow> rows = grouped.rows().stream()
                .map(row -> new SearchRow(
                        row.keys().isEmpty() ? "" : row.keys().getFirst(),
                        row.clicks(),
                        row.impressions(),
                        row.ctr(),
                        row.position()))
                .toList();
        return new SearchConsoleReport(
                property.propertyUrl(),
                from,
                to,
                dimension,
                total.clicks(),
                total.impressions(),
                total.ctr(),
                total.position(),
                grouped.aggregationType(),
                rows,
                rows.size() == REPORT_ROW_LIMIT,
                "Google may omit anonymized queries and lower-ranked rows; the Search Analytics API does not guarantee every row is returned.");
    }

    static String normalizeProperty(String value) {
        if (value == null || value.isBlank() || value.length() > 2048) {
            throw new ControlPlaneException(
                    400,
                    "SEARCH_CONSOLE_PROPERTY_INVALID",
                    "Enter a Search Console property URL or sc-domain: property.");
        }
        String property = value.strip();
        if (property.startsWith("sc-domain:")) {
            String domain = property.substring("sc-domain:".length()).strip().toLowerCase(Locale.ROOT);
            if (domain.isEmpty()
                    || domain.contains("/")
                    || domain.contains(":")
                    || domain.contains("?")
                    || domain.contains("#")) {
                throw new ControlPlaneException(
                        400, "SEARCH_CONSOLE_PROPERTY_INVALID", "Use sc-domain:example.com for a domain property.");
            }
            try {
                String ascii = java.net.IDN.toASCII(domain);
                if (ascii.length() > 253
                        || !ascii.matches("(?i)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}")) {
                    throw new IllegalArgumentException();
                }
                return "sc-domain:" + ascii;
            } catch (IllegalArgumentException error) {
                throw new ControlPlaneException(
                        400,
                        "SEARCH_CONSOLE_PROPERTY_INVALID",
                        "Enter a valid domain property such as sc-domain:example.com.");
            }
        }
        try {
            URI uri = URI.create(property);
            if (!("https".equalsIgnoreCase(uri.getScheme()) || "http".equalsIgnoreCase(uri.getScheme()))
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
                    "SEARCH_CONSOLE_PROPERTY_INVALID",
                    "Use an http(s) URL-prefix property without query or fragment, or an sc-domain: property.");
        }
    }

    private Site readableSite(UUID siteId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        return site;
    }

    private StoredProperty requiredProperty(UUID siteId) {
        StoredProperty property = readProperty(siteId);
        if (property == null) {
            throw new ControlPlaneException(
                    409, "SEARCH_CONSOLE_PROPERTY_NOT_CONFIGURED", "Configure a Search Console property first.");
        }
        return property;
    }

    private StoredProperty readProperty(UUID siteId) {
        try (var connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select property_url,updated_at from search_console_property where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet result = statement.executeQuery()) {
                return result.next()
                        ? new StoredProperty(
                                result.getString(1), result.getTimestamp(2).toInstant())
                        : null;
            }
        } catch (Exception error) {
            throw new IllegalStateException("Could not load Search Console property", error);
        }
    }

    private static LocalDate parseDate(String value, LocalDate fallback) {
        if (value == null || value.isBlank()) return fallback;
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException error) {
            throw new ControlPlaneException(400, "SEARCH_CONSOLE_RANGE_INVALID", "Dates must use YYYY-MM-DD format.");
        }
    }

    private record StoredProperty(String propertyUrl, java.time.Instant updatedAt) {}

    public record PropertyView(
            boolean configured,
            String propertyUrl,
            java.time.Instant updatedAt,
            String credentialMode,
            boolean canManage) {}

    public record ValidationResult(boolean accessible, String propertyUrl, String permissionLevel, String message) {}

    public record SearchRow(String key, double clicks, double impressions, double ctr, double position) {}

    public record SearchConsoleReport(
            String propertyUrl,
            LocalDate from,
            LocalDate to,
            String dimension,
            double clicks,
            double impressions,
            double ctr,
            double averagePosition,
            String aggregationType,
            List<SearchRow> rows,
            boolean mayBeTruncated,
            String dataLimitNote) {}
}
