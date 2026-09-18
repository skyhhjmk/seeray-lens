package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.*;
import javax.sql.DataSource;

@ApplicationScoped
public class WorkspaceRollupService {
    private static final int MAX_DAYS = 366;
    private static final int MAX_SITES = 500;

    private final DataSource dataSource;
    private final SiteService sites;

    @Inject
    public WorkspaceRollupService(DataSource dataSource, SiteService sites) {
        this.dataSource = dataSource;
        this.sites = sites;
    }

    public RollupReport report(UUID workspaceId, List<UUID> requestedSiteIds, String fromValue, String toValue) {
        // SiteService enforces workspace membership before any site IDs reach SQL.
        List<Site> accessibleSites = sites.list(workspaceId).stream()
                .sorted(Comparator.comparing(site -> site.name.toLowerCase(Locale.ROOT)))
                .toList();
        LocalDate defaultTo = LocalDate.now(ZoneOffset.UTC);
        LocalDate to = parseDate(toValue, defaultTo);
        LocalDate from = parseDate(fromValue, to.minusDays(29));
        if (from.isAfter(to) || from.plusDays(MAX_DAYS - 1L).isBefore(to))
            throw new IllegalArgumentException("from/to must be an inclusive range of at most 366 days");

        LinkedHashMap<UUID, Site> accessibleById = new LinkedHashMap<>();
        accessibleSites.forEach(site -> accessibleById.put(site.id, site));
        List<Site> selected;
        if (requestedSiteIds == null || requestedSiteIds.isEmpty()) {
            selected = accessibleSites;
        } else {
            LinkedHashSet<UUID> unique = new LinkedHashSet<>(requestedSiteIds);
            if (unique.size() > MAX_SITES) throw tooManySites();
            if (!accessibleById.keySet().containsAll(unique)) throw siteNotFound();
            selected = unique.stream().map(accessibleById::get).toList();
        }
        if (selected.size() > MAX_SITES) throw tooManySites();
        if (selected.isEmpty()) return emptyReport(from, to);

        List<UUID> ids = selected.stream().map(site -> site.id).toList();
        Map<UUID, MutableSiteMetric> metrics = new LinkedHashMap<>();
        selected.forEach(site -> metrics.put(site.id, new MutableSiteMetric(site)));
        TreeMap<LocalDate, MutableDaily> daily = new TreeMap<>();
        Map<String, Long> channels = new HashMap<>();
        try (Connection connection = dataSource.getConnection()) {
            loadSiteTotals(connection, ids, from, to, metrics);
            loadSiteVisitors(connection, ids, from, to, metrics);
            loadDailyTotals(connection, ids, from, to, daily);
            loadDailyVisitors(connection, ids, from, to, daily);
            loadChannels(connection, ids, from, to, channels);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query workspace roll-up analytics", error);
        }

        long pageViews = 0;
        long sessions = 0;
        long siteVisitors = 0;
        long bouncedSessions = 0;
        List<SiteMetric> siteRows = new ArrayList<>();
        for (MutableSiteMetric metric : metrics.values()) {
            pageViews += metric.pageViews;
            sessions += metric.sessions;
            siteVisitors += metric.siteVisitors;
            bouncedSessions += metric.bouncedSessions;
            siteRows.add(new SiteMetric(
                    metric.site.id,
                    metric.site.name,
                    metric.site.timezone,
                    metric.site.trackingEnabled,
                    metric.pageViews,
                    metric.siteVisitors,
                    metric.sessions,
                    ratio(metric.bouncedSessions, metric.sessions)));
        }
        List<DailyMetric> dailyRows = new ArrayList<>();
        for (LocalDate date = from; !date.isAfter(to); date = date.plusDays(1)) {
            MutableDaily value = daily.getOrDefault(date, new MutableDaily());
            dailyRows.add(new DailyMetric(date, value.pageViews, value.sessions, value.siteVisitors));
        }
        List<ChannelMetric> channelRows = channels.entrySet().stream()
                .sorted(Map.Entry.<String, Long>comparingByValue().reversed().thenComparing(Map.Entry::getKey))
                .map(entry -> new ChannelMetric(entry.getKey(), entry.getValue()))
                .toList();
        return new RollupReport(
                from,
                to,
                selected.size(),
                pageViews,
                siteVisitors,
                sessions,
                ratio(bouncedSessions, sessions),
                dailyRows,
                siteRows,
                channelRows);
    }

    private static void loadSiteTotals(
            Connection connection, List<UUID> ids, LocalDate from, LocalDate to, Map<UUID, MutableSiteMetric> metrics)
            throws SQLException {
        String sql = "select site_id,coalesce(sum(page_view_count),0),coalesce(sum(session_count),0),"
                + "coalesce(sum(bounced_session_count),0) from analytics_site_daily where site_id in ("
                + placeholders(ids.size()) + ") and business_date between ? and ? group by site_id";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            bindScope(statement, ids, from, to);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    MutableSiteMetric metric = metrics.get(rows.getObject(1, UUID.class));
                    if (metric == null) continue;
                    metric.pageViews = rows.getLong(2);
                    metric.sessions = rows.getLong(3);
                    metric.bouncedSessions = rows.getLong(4);
                }
            }
        }
    }

    private static void loadSiteVisitors(
            Connection connection, List<UUID> ids, LocalDate from, LocalDate to, Map<UUID, MutableSiteMetric> metrics)
            throws SQLException {
        String sql = "select site_id,count(distinct visitor_id) from visitor_day_fact where site_id in ("
                + placeholders(ids.size()) + ") and business_date between ? and ? group by site_id";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            bindScope(statement, ids, from, to);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    MutableSiteMetric metric = metrics.get(rows.getObject(1, UUID.class));
                    if (metric != null) metric.siteVisitors = rows.getLong(2);
                }
            }
        }
    }

    private static void loadDailyTotals(
            Connection connection, List<UUID> ids, LocalDate from, LocalDate to, Map<LocalDate, MutableDaily> daily)
            throws SQLException {
        String sql = "select business_date,coalesce(sum(page_view_count),0),coalesce(sum(session_count),0) "
                + "from analytics_site_daily where site_id in (" + placeholders(ids.size())
                + ") and business_date between ? and ? group by business_date";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            bindScope(statement, ids, from, to);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    MutableDaily value =
                            daily.computeIfAbsent(rows.getObject(1, LocalDate.class), ignored -> new MutableDaily());
                    value.pageViews = rows.getLong(2);
                    value.sessions = rows.getLong(3);
                }
            }
        }
    }

    private static void loadDailyVisitors(
            Connection connection, List<UUID> ids, LocalDate from, LocalDate to, Map<LocalDate, MutableDaily> daily)
            throws SQLException {
        String sql = "select business_date,sum(site_visitors) from (select business_date,site_id,"
                + "count(distinct visitor_id) site_visitors from visitor_day_fact where site_id in ("
                + placeholders(ids.size())
                + ") and business_date between ? and ? group by business_date,site_id) visitors "
                + "group by business_date";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            bindScope(statement, ids, from, to);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    MutableDaily value =
                            daily.computeIfAbsent(rows.getObject(1, LocalDate.class), ignored -> new MutableDaily());
                    value.siteVisitors = rows.getLong(2);
                }
            }
        }
    }

    private static void loadChannels(
            Connection connection, List<UUID> ids, LocalDate from, LocalDate to, Map<String, Long> channels)
            throws SQLException {
        String sql = "select channel,coalesce(sum(session_count),0) from analytics_traffic_daily where site_id in ("
                + placeholders(ids.size()) + ") and business_date between ? and ? group by channel";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            bindScope(statement, ids, from, to);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) channels.put(rows.getString(1), rows.getLong(2));
            }
        }
    }

    private static void bindScope(PreparedStatement statement, List<UUID> ids, LocalDate from, LocalDate to)
            throws SQLException {
        int index = 1;
        for (UUID id : ids) statement.setObject(index++, id);
        statement.setObject(index++, from);
        statement.setObject(index, to);
    }

    private static String placeholders(int count) {
        return String.join(",", Collections.nCopies(count, "?"));
    }

    private static LocalDate parseDate(String value, LocalDate fallback) {
        if (value == null || value.isBlank()) return fallback;
        try {
            return LocalDate.parse(value);
        } catch (java.time.format.DateTimeParseException invalidDate) {
            throw new IllegalArgumentException("from and to must be ISO calendar dates", invalidDate);
        }
    }

    private static double ratio(long numerator, long denominator) {
        return denominator == 0 ? 0 : (double) numerator / denominator;
    }

    private static RollupReport emptyReport(LocalDate from, LocalDate to) {
        List<DailyMetric> daily = new ArrayList<>();
        for (LocalDate date = from; !date.isAfter(to); date = date.plusDays(1))
            daily.add(new DailyMetric(date, 0, 0, 0));
        return new RollupReport(from, to, 0, 0, 0, 0, 0, daily, List.of(), List.of());
    }

    private static ControlPlaneException siteNotFound() {
        return new ControlPlaneException(404, "SITE_NOT_FOUND", "Site not found in this workspace");
    }

    private static ControlPlaneException tooManySites() {
        return new ControlPlaneException(400, "TOO_MANY_SITES", "A roll-up report can include at most 500 sites");
    }

    private static final class MutableSiteMetric {
        private final Site site;
        private long pageViews;
        private long siteVisitors;
        private long sessions;
        private long bouncedSessions;

        private MutableSiteMetric(Site site) {
            this.site = site;
        }
    }

    private static final class MutableDaily {
        private long pageViews;
        private long sessions;
        private long siteVisitors;
    }

    public record RollupReport(
            LocalDate from,
            LocalDate to,
            int siteCount,
            long pageViews,
            long siteVisitors,
            long sessions,
            double bounceRate,
            List<DailyMetric> daily,
            List<SiteMetric> sites,
            List<ChannelMetric> channels) {}

    public record DailyMetric(LocalDate date, long pageViews, long sessions, long siteVisitors) {}

    public record SiteMetric(
            UUID siteId,
            String name,
            String timezone,
            boolean trackingEnabled,
            long pageViews,
            long siteVisitors,
            long sessions,
            double bounceRate) {}

    public record ChannelMetric(String channel, long sessions) {}
}
