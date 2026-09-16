package io.seeray.lens.application;

import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.*;
import java.util.*;
import javax.sql.DataSource;

@ApplicationScoped
public class AnalyticsQueryService {
    private static final int MAX_DAYS = 366;
    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;

    @Inject
    public AnalyticsQueryService(DataSource dataSource, SiteService sites, WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
    }

    public Range range(UUID siteId, String fromValue, String toValue) {
        Site site = sites.site(siteId);
        access.member(site.organization.id); // deliberately maps cross-workspace sites to the existing 404 policy
        ZoneId zone = ZoneId.of(site.timezone);
        LocalDate today = LocalDate.now(zone);
        LocalDate from = fromValue == null || fromValue.isBlank() ? today.minusDays(29) : parse(fromValue);
        LocalDate to = toValue == null || toValue.isBlank() ? today : parse(toValue);
        if (from.isAfter(to) || from.plusDays(MAX_DAYS - 1L).isBefore(to))
            throw new IllegalArgumentException("from/to must be an inclusive range of at most 366 days");
        return new Range(from, to);
    }

    public Overview overview(UUID site, Range range) {
        String sql =
                "select coalesce(sum(page_view_count),0),coalesce(sum(session_count),0),coalesce(sum(bounced_session_count),0),coalesce(sum(session_duration_sum_ms),0),coalesce(sum(session_duration_count),0) from analytics_site_daily where site_id=? and business_date between ? and ?";
        try (Connection c = dataSource.getConnection();
                PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, site);
            p.setObject(2, range.from);
            p.setObject(3, range.to);
            try (ResultSet r = p.executeQuery()) {
                r.next();
                long sessions = r.getLong(2), durationCount = r.getLong(5);
                return new Overview(
                        range.from,
                        range.to,
                        r.getLong(1),
                        visitors(c, site, range),
                        sessions,
                        ratio(r.getLong(3), sessions),
                        durationCount == 0 ? 0 : r.getLong(4) / durationCount);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query analytics", e);
        }
    }

    public List<Daily> timeseries(UUID site, Range range) {
        List<Daily> out = new ArrayList<>();
        String sql =
                "select business_date,page_view_count,session_count from analytics_site_daily where site_id=? and business_date between ? and ? order by business_date";
        try (Connection c = dataSource.getConnection();
                PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, site);
            p.setObject(2, range.from);
            p.setObject(3, range.to);
            try (ResultSet r = p.executeQuery()) {
                while (r.next()) {
                    LocalDate day = r.getObject(1, LocalDate.class);
                    out.add(new Daily(day, r.getLong(2), visitors(c, site, new Range(day, day)), r.getLong(3)));
                }
            }
            return out;
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query analytics", e);
        }
    }

    public List<Page> pages(UUID site, Range range) {
        return list(
                site,
                range,
                "select path,sum(page_view_count) n from analytics_page_daily where site_id=? and business_date between ? and ? group by path order by n desc,path asc",
                r -> new Page(r.getString(1), r.getLong(2)));
    }

    public List<Traffic> traffic(UUID site, Range range) {
        return list(
                site,
                range,
                "select channel,nullif(source,''),nullif(medium,''),nullif(campaign,''),sum(session_count) n from analytics_traffic_daily where site_id=? and business_date between ? and ? group by channel,source,medium,campaign order by n desc,channel asc",
                r -> new Traffic(r.getString(1), r.getString(2), r.getString(3), r.getString(4), r.getLong(5)));
    }

    public List<Event> events(UUID site, Range range) {
        return list(
                site,
                range,
                "select event_type,sum(event_count) n from analytics_event_daily where site_id=? and business_date between ? and ? group by event_type order by n desc,event_type asc",
                r -> new Event(r.getString(1), r.getLong(2)));
    }

    public VisitorOverview visitors(UUID site, Range range) {
        String sql =
                "select coalesce(sum(session_count),0),coalesce(sum(new_session_count),0),coalesce(sum(returning_session_count),0),coalesce(sum(bounced_session_count),0),coalesce(sum(session_duration_sum_ms),0),coalesce(sum(session_duration_count),0) from analytics_site_daily where site_id=? and business_date between ? and ?";
        try (Connection c = dataSource.getConnection();
                PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, site);
            p.setObject(2, range.from);
            p.setObject(3, range.to);
            try (ResultSet r = p.executeQuery()) {
                r.next();
                long sessions = r.getLong(1), durationCount = r.getLong(6);
                return new VisitorOverview(
                        visitors(c, site, range),
                        sessions,
                        r.getLong(2),
                        r.getLong(3),
                        ratio(r.getLong(4), sessions),
                        durationCount == 0 ? 0 : r.getLong(5) / durationCount);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query visitors", e);
        }
    }

    public List<Goal> goals(UUID site, Range range) {
        return list(
                site,
                range,
                """
                select g.name,sum(d.conversion_count),sum(d.converted_session_count),coalesce(sum(d.value_sum),0),
                  case when sum(s.session_count)=0 then 0 else sum(d.converted_session_count)::double precision/sum(s.session_count) end
                from analytics_goal_conversion_daily d join goal_definition g on g.id=d.goal_id
                  left join analytics_site_daily s on s.site_id=d.site_id and s.business_date=d.business_date
                where d.site_id=? and d.business_date between ? and ?
                group by g.id,g.name order by sum(d.conversion_count) desc,g.name asc
                """,
                r -> new Goal(r.getString(1), r.getLong(2), r.getLong(3), r.getBigDecimal(4), r.getDouble(5)));
    }

    private long visitors(Connection c, UUID site, Range range) throws SQLException {
        try (PreparedStatement p = c.prepareStatement(
                "select count(distinct visitor_id) from visitor_day_fact where site_id=? and business_date between ? and ?")) {
            p.setObject(1, site);
            p.setObject(2, range.from);
            p.setObject(3, range.to);
            try (ResultSet r = p.executeQuery()) {
                r.next();
                return r.getLong(1);
            }
        }
    }

    private <T> List<T> list(UUID site, Range range, String sql, Row<T> row) {
        List<T> out = new ArrayList<>();
        try (Connection c = dataSource.getConnection();
                PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, site);
            p.setObject(2, range.from);
            p.setObject(3, range.to);
            try (ResultSet r = p.executeQuery()) {
                while (r.next()) out.add(row.map(r));
            }
            return out;
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query analytics", e);
        }
    }

    private static LocalDate parse(String value) {
        try {
            return LocalDate.parse(value);
        } catch (Exception e) {
            throw new IllegalArgumentException("from and to must use YYYY-MM-DD");
        }
    }

    private static double ratio(long value, long total) {
        return total == 0 ? 0d : (double) value / total;
    }

    private interface Row<T> {
        T map(ResultSet row) throws SQLException;
    }

    public record Range(LocalDate from, LocalDate to) {}

    public record Overview(
            LocalDate from,
            LocalDate to,
            long pageViews,
            long uniqueVisitors,
            long sessions,
            double bounceRate,
            long averageSessionDurationMs) {}

    public record Daily(LocalDate date, long pageViews, long uniqueVisitors, long sessions) {}

    public record Page(String path, long pageViews) {}

    public record Traffic(String channel, String source, String medium, String campaign, long sessions) {}

    public record Event(String eventType, long count) {}

    public record VisitorOverview(
            long uniqueVisitors,
            long sessions,
            long newSessions,
            long returningSessions,
            double bounceRate,
            long averageSessionDurationMs) {}

    public record Goal(
            String name, long count, long convertedSessions, java.math.BigDecimal value, double conversionRate) {}
}
