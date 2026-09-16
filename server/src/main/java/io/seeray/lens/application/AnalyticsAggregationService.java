package io.seeray.lens.application;

import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.*;
import java.util.*;
import javax.sql.DataSource;

/** Builds the small query-facing analytics tables from immutable raw events and semantic facts. */
@ApplicationScoped
public class AnalyticsAggregationService {
    private final DataSource dataSource;
    private final AnalyticsFactBuilder facts;

    @Inject
    public AnalyticsAggregationService(DataSource dataSource, AnalyticsFactBuilder facts) {
        this.dataSource = dataSource;
        this.facts = facts;
    }

    public void rebuild(UUID siteId, LocalDate from, LocalDate to) {
        if (from.isAfter(to)) throw new IllegalArgumentException("from must not be after to");
        try (Connection c = dataSource.getConnection()) {
            String timezone = timezone(c, siteId);
            ZoneId zone = ZoneId.of(timezone);
            facts.rebuild(
                    siteId,
                    from.atStartOfDay(zone).toInstant(),
                    to.plusDays(1).atStartOfDay(zone).toInstant());
            delete(c, siteId, from, to);
            siteDaily(c, siteId, from, to, timezone);
            pages(c, siteId, from, to, timezone);
            traffic(c, siteId, from, to, timezone);
            events(c, siteId, from, to, timezone);
            goals(c, siteId, from, to, timezone);
            configuredGoals(c, siteId, from, to, timezone);
        } catch (SQLException e) {
            throw new IllegalStateException("Could not rebuild analytics aggregates", e);
        }
    }

    /** Rebuilds only today and yesterday's dashboard rows, allowing late events to settle. */
    @Scheduled(every = "5m", identity = "analytics-recent-refresh")
    void refreshRecent() {
        try (Connection c = dataSource.getConnection();
                PreparedStatement p = c.prepareStatement(
                        "select distinct site_id from raw_event where received_at >= now() - interval '2 days'")) {
            try (ResultSet r = p.executeQuery()) {
                while (r.next()) {
                    UUID siteId = r.getObject(1, UUID.class);
                    String tz = timezone(c, siteId);
                    LocalDate today = LocalDate.now(ZoneId.of(tz));
                    rebuild(siteId, today.minusDays(1), today);
                }
            }
        } catch (Exception ignored) {
            // A later run reconciles the same two business days; ingestion must never be disrupted by this job.
        }
    }

    private static void delete(Connection c, UUID site, LocalDate from, LocalDate to) throws SQLException {
        for (String table : List.of(
                "analytics_site_daily",
                "analytics_page_daily",
                "analytics_traffic_daily",
                "analytics_event_daily",
                "analytics_goal_daily",
                "analytics_goal_conversion_daily")) {
            try (PreparedStatement p =
                    c.prepareStatement("delete from " + table + " where site_id=? and business_date between ? and ?")) {
                p.setObject(1, site);
                p.setObject(2, from);
                p.setObject(3, to);
                p.executeUpdate();
            }
        }
    }

    private static void siteDaily(Connection c, UUID site, LocalDate from, LocalDate to, String tz)
            throws SQLException {
        String sql =
                """
                insert into analytics_site_daily(site_id,business_date,page_view_count,session_count,new_session_count,returning_session_count,bounced_session_count,session_duration_sum_ms,session_duration_count)
                select ?, d::date, coalesce(p.page_views,0), coalesce(s.sessions,0), coalesce(s.new_sessions,0), coalesce(s.returning_sessions,0), coalesce(s.bounced,0), coalesce(s.duration_sum,0), coalesce(s.duration_count,0)
                from generate_series(?::date, ?::date, interval '1 day') d
                left join (select ((case when occurred_at < received_at - interval '24 hours' or occurred_at > received_at + interval '24 hours' then received_at else occurred_at end) at time zone ?)::date business_date, count(*) page_views from raw_event where site_id=? and event_type='page_view' group by business_date) p on p.business_date=d::date
                left join (select (started_at at time zone ?)::date business_date, count(*) sessions, count(*) filter (where visitor_type='new') new_sessions, count(*) filter (where visitor_type='returning') returning_sessions, count(*) filter (where is_bounce) bounced, coalesce(sum(duration_ms),0) duration_sum, count(*) duration_count from analytics_session where site_id=? group by business_date) s on s.business_date=d::date
                """;
        try (PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, site);
            p.setObject(2, from);
            p.setObject(3, to);
            p.setString(4, tz);
            p.setObject(5, site);
            p.setString(6, tz);
            p.setObject(7, site);
            p.executeUpdate();
        }
    }

    private static void pages(Connection c, UUID site, LocalDate from, LocalDate to, String tz) throws SQLException {
        String sql =
                """
                insert into analytics_page_daily(site_id,business_date,path,page_view_count)
                select * from (select site_id, ((case when occurred_at < received_at - interval '24 hours' or occurred_at > received_at + interval '24 hours' then received_at else occurred_at end) at time zone ?)::date business_date, page_path, count(*) page_view_count
                from raw_event where site_id=? and event_type='page_view' and page_path is not null group by site_id,business_date,page_path) pages
                where business_date between ? and ?
                """;
        try (PreparedStatement p = c.prepareStatement(sql)) {
            p.setString(1, tz);
            p.setObject(2, site);
            p.setObject(3, from);
            p.setObject(4, to);
            p.executeUpdate();
        }
    }

    private static void events(Connection c, UUID site, LocalDate from, LocalDate to, String tz) throws SQLException {
        String sql =
                """
                insert into analytics_event_daily(site_id,business_date,event_type,event_count)
                select * from (select site_id, ((case when occurred_at < received_at - interval '24 hours' or occurred_at > received_at + interval '24 hours' then received_at else occurred_at end) at time zone ?)::date business_date, event_type, count(*) event_count
                from raw_event where site_id=? group by site_id,business_date,event_type) events
                where business_date between ? and ?
                """;
        try (PreparedStatement p = c.prepareStatement(sql)) {
            p.setString(1, tz);
            p.setObject(2, site);
            p.setObject(3, from);
            p.setObject(4, to);
            p.executeUpdate();
        }
    }

    private static void goals(Connection c, UUID site, LocalDate from, LocalDate to, String tz) throws SQLException {
        String sql =
                """
                insert into analytics_goal_daily(site_id,business_date,goal_name,goal_count)
                select * from (select site_id, ((case when occurred_at < received_at - interval '24 hours' or occurred_at > received_at + interval '24 hours' then received_at else occurred_at end) at time zone ?)::date business_date,
                coalesce(nullif(event_data->>'name',''),nullif(event_data->'data'->>'name',''),'Unnamed goal') goal_name, count(*) goal_count
                from raw_event where site_id=? and event_type='goal' group by site_id,business_date,goal_name) goals
                where business_date between ? and ?
                """;
        try (PreparedStatement p = c.prepareStatement(sql)) {
            p.setString(1, tz);
            p.setObject(2, site);
            p.setObject(3, from);
            p.setObject(4, to);
            p.executeUpdate();
        }
    }

    /** A conversion is one qualifying session per configured goal and business day. */
    private static void configuredGoals(Connection c, UUID site, LocalDate from, LocalDate to, String tz)
            throws SQLException {
        String sql =
                """
                insert into analytics_goal_conversion_daily(site_id,business_date,goal_id,conversion_count,converted_session_count,value_sum)
                select site_id,business_date,goal_id,conversion_count,converted_session_count,value_sum from (
                  select ? as site_id, ((case when e.occurred_at < e.received_at - interval '24 hours' or e.occurred_at > e.received_at + interval '24 hours' then e.received_at else e.occurred_at end) at time zone ?)::date business_date,
                         g.id goal_id, count(*) conversion_count, count(distinct e.client_session_id) converted_session_count, coalesce(sum(g.fixed_value), 0) value_sum
                  from raw_event e join goal_definition g on g.site_id=e.site_id and g.enabled
                  where e.site_id=?
                    and ((g.trigger_type='event' and e.event_type=g.event_type and (g.event_name is null or coalesce(nullif(e.event_data->>'name',''), nullif(e.event_data->'data'->>'name',''))=g.event_name))
                      or (g.trigger_type='page_view' and e.event_type='page_view' and ((g.path_match_mode='exact' and e.page_path=g.path_pattern) or (g.path_match_mode='contains' and position(g.path_pattern in coalesce(e.page_path,'')) > 0))))
                  group by business_date,g.id
                ) counted where business_date between ? and ?
                """;
        try (PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, site);
            p.setString(2, tz);
            p.setObject(3, site);
            p.setObject(4, from);
            p.setObject(5, to);
            p.executeUpdate();
        }
    }

    private static void traffic(Connection c, UUID site, LocalDate from, LocalDate to, String tz) throws SQLException {
        Set<String> internal = domains(c, site);
        // Preserve the business date in the primary key: populate day-by-day from the fact sessions.
        try (PreparedStatement read = c.prepareStatement(
                        "select (started_at at time zone ?)::date,initial_referrer_host,initial_page_host,initial_utm_source,initial_utm_medium,initial_utm_campaign from analytics_session where site_id=? and (started_at at time zone ?)::date between ? and ?");
                PreparedStatement write = c.prepareStatement(
                        "insert into analytics_traffic_daily(site_id,business_date,channel,source,medium,campaign,session_count) values(?,?,?,?,?,?,?) on conflict(site_id,business_date,channel,source,medium,campaign) do update set session_count=analytics_traffic_daily.session_count + excluded.session_count")) {
            read.setString(1, tz);
            read.setObject(2, site);
            read.setString(3, tz);
            read.setObject(4, from);
            read.setObject(5, to);
            try (ResultSet r = read.executeQuery()) {
                while (r.next()) {
                    String ref = r.getString(2),
                            host = r.getString(3),
                            source = r.getString(4),
                            medium = r.getString(5),
                            campaign = r.getString(6);
                    String channel = source != null && !source.isBlank()
                            ? "campaign"
                            : ref == null
                                            || ref.isBlank()
                                            || ref.equalsIgnoreCase(host)
                                            || internal.contains(ref.toLowerCase(Locale.ROOT))
                                    ? "direct"
                                    : "referral";
                    write.setObject(1, site);
                    write.setObject(2, r.getObject(1, LocalDate.class));
                    write.setString(3, channel);
                    write.setString(4, empty(channel.equals("referral") ? ref : source));
                    write.setString(5, empty(medium));
                    write.setString(6, empty(campaign));
                    write.setLong(7, 1);
                    write.addBatch();
                }
            }
            write.executeBatch();
        }
    }

    private static String empty(String value) {
        return value == null ? "" : value;
    }

    private static Set<String> domains(Connection c, UUID site) throws SQLException {
        Set<String> out = new HashSet<>();
        try (PreparedStatement p =
                c.prepareStatement("select host from site_allowed_domain where site_id=? and enabled")) {
            p.setObject(1, site);
            try (ResultSet r = p.executeQuery()) {
                while (r.next()) out.add(r.getString(1).toLowerCase(Locale.ROOT));
            }
        }
        return out;
    }

    private static String timezone(Connection c, UUID site) throws SQLException {
        try (PreparedStatement p = c.prepareStatement("select timezone from site where id=?")) {
            p.setObject(1, site);
            try (ResultSet r = p.executeQuery()) {
                if (!r.next()) throw new IllegalArgumentException("site not found");
                return r.getString(1);
            }
        }
    }
}
