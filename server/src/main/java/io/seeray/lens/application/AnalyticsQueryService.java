package io.seeray.lens.application;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
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
    private final ObjectMapper mapper;

    @Inject
    public AnalyticsQueryService(
            DataSource dataSource, SiteService sites, WorkspaceAccess access, ObjectMapper mapper) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
        this.mapper = mapper;
    }

    public AnalyticsQueryService(DataSource dataSource, SiteService sites, WorkspaceAccess access) {
        this(dataSource, sites, access, new ObjectMapper());
    }

    public Range range(UUID siteId, String fromValue, String toValue) {
        return range(siteId, fromValue, toValue, MAX_DAYS);
    }

    public Range range(UUID siteId, String fromValue, String toValue, int maximumDays) {
        if (maximumDays < 1) throw new IllegalArgumentException("maximumDays must be positive");
        Site site = sites.site(siteId);
        access.member(site.organization.id); // deliberately maps cross-workspace sites to the existing 404 policy
        ZoneId zone = ZoneId.of(site.timezone);
        LocalDate today = LocalDate.now(zone);
        LocalDate from = fromValue == null || fromValue.isBlank() ? today.minusDays(29) : parse(fromValue);
        LocalDate to = toValue == null || toValue.isBlank() ? today : parse(toValue);
        if (from.isAfter(to) || from.plusDays(maximumDays - 1L).isBefore(to))
            throw new IllegalArgumentException(
                    "from/to must be an inclusive range of at most " + maximumDays + " days");
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

    public List<PageTitle> pageTitles(UUID site, Range range) {
        return list(
                site,
                range,
                "select path,nullif(title,''),sum(page_view_count) from analytics_page_title_daily where site_id=? and business_date between ? and ? group by path,title order by sum(page_view_count) desc,path,title limit 100",
                r -> new PageTitle(r.getString(1), r.getString(2), r.getLong(3)));
    }

    public List<Traffic> traffic(UUID site, Range range) {
        return list(
                site,
                range,
                "select channel,nullif(source,''),nullif(medium,''),nullif(campaign,''),nullif(term,''),nullif(content,''),sum(session_count) n from analytics_traffic_daily where site_id=? and business_date between ? and ? group by channel,source,medium,campaign,term,content order by n desc,channel asc",
                r -> new Traffic(
                        r.getString(1),
                        r.getString(2),
                        r.getString(3),
                        r.getString(4),
                        r.getString(5),
                        r.getString(6),
                        r.getLong(7)));
    }

    public List<Event> events(UUID site, Range range) {
        return list(
                site,
                range,
                "select event_type,sum(event_count) n from analytics_event_daily where site_id=? and event_type<>'web_vital' and business_date between ? and ? group by event_type order by n desc,event_type asc",
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

    /** Privacy-preserving session log: anonymous site-local IDs only, never IP, UA fingerprint, or cross-site IDs. */
    public List<VisitorLog> visitorLog(UUID site, Range range, int requestedLimit) {
        int limit = Math.max(1, Math.min(requestedLimit, 200));
        String sql =
                """
                select v.client_visitor_id,s.started_at,s.last_activity_at,s.entry_page,s.exit_page,s.page_view_count,s.event_count,s.duration_ms,s.is_bounce,s.visitor_type
                from analytics_session s join analytics_visitor v on v.id=s.visitor_id
                where s.site_id=? and (s.started_at at time zone (select timezone from site where id=?))::date between ? and ?
                order by s.started_at desc limit ?
                """;
        List<VisitorLog> out = new ArrayList<>();
        try (Connection c = dataSource.getConnection();
                PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, site);
            p.setObject(2, site);
            p.setObject(3, range.from);
            p.setObject(4, range.to);
            p.setInt(5, limit);
            try (ResultSet r = p.executeQuery()) {
                while (r.next())
                    out.add(new VisitorLog(
                            r.getString(1),
                            r.getTimestamp(2).toInstant(),
                            r.getTimestamp(3).toInstant(),
                            r.getString(4),
                            r.getString(5),
                            r.getInt(6),
                            r.getInt(7),
                            r.getLong(8),
                            r.getBoolean(9),
                            r.getString(10)));
            }
            return out;
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query visitor log", e);
        }
    }

    /** Reads current visit facts from the durable event stream, not the delayed aggregate tables. */
    public List<LiveVisitor> realtime(UUID site, int requestedWindowMinutes, int requestedLimit) {
        int windowMinutes = Math.max(1, Math.min(requestedWindowMinutes, 60));
        int limit = Math.max(1, Math.min(requestedLimit, 100));
        String sql =
                """
                with active_sessions as (
                  select client_visitor_id,client_session_id,max(received_at) last_activity_at
                  from raw_event
                  where site_id=? and received_at >= now() - (? * interval '1 minute')
                    and nullif(client_visitor_id,'') is not null and nullif(client_session_id,'') is not null
                  group by client_visitor_id,client_session_id
                  order by max(received_at) desc limit ?
                ), session_events as (
                  select e.client_visitor_id,e.client_session_id,e.ingest_id,e.received_at,e.event_type,
                    e.page_path,e.page_title,e.event_data,e.user_id_hash
                  from raw_event e join active_sessions a on a.client_visitor_id=e.client_visitor_id
                    and a.client_session_id=e.client_session_id
                  where e.site_id=?
                ), session_summary as (
                  select client_visitor_id,client_session_id,min(received_at) started_at,max(received_at) last_activity_at,
                    count(*)::integer event_count,count(*) filter(where event_type='page_view')::integer page_views,
                    (array_agg(page_path order by received_at,ingest_id) filter(where event_type='page_view'))[1] entry_page,
                    case when count(distinct user_id_hash)=1 then min(user_id_hash) end session_user_id_hash
                  from session_events group by client_visitor_id,client_session_id
                ), latest_event as (
                  select distinct on (client_visitor_id,client_session_id) client_visitor_id,client_session_id,
                    event_type,page_path,page_title
                  from session_events order by client_visitor_id,client_session_id,received_at desc,ingest_id desc
                ), ranked_actions as (
                  select *,row_number() over(partition by client_visitor_id,client_session_id
                    order by received_at desc,ingest_id desc) action_rank from session_events
                ), actions as (
                  select client_visitor_id,client_session_id,
                    jsonb_agg(jsonb_build_object('at',received_at,'eventType',event_type,'path',page_path,'title',page_title)
                      order by received_at desc,ingest_id desc)::text actions_json
                  from ranked_actions where action_rank<=20 group by client_visitor_id,client_session_id
                ), visit_context as (
                  select distinct on (client_visitor_id,client_session_id) client_visitor_id,client_session_id,
                    event_data->'context' context
                  from session_events where event_type='page_view'
                  order by client_visitor_id,client_session_id,received_at,ingest_id
                ), active_browser_ids as (
                  select distinct client_visitor_id from active_sessions
                ), browser_session_identities as (
                  select e.client_visitor_id,e.client_session_id,
                    case when count(distinct e.user_id_hash)=1 then min(e.user_id_hash) end user_id_hash,
                    count(distinct e.user_id_hash)>1 has_conflict
                  from raw_event e join active_browser_ids b using(client_visitor_id)
                  where e.site_id=? group by e.client_visitor_id,e.client_session_id
                ), browser_identity_stats as (
                  select client_visitor_id,count(distinct user_id_hash) identity_count,min(user_id_hash) user_id_hash,
                    coalesce(bool_or(has_conflict),false) has_conflict
                  from browser_session_identities group by client_visitor_id
                ), session_identity as (
                  select s.*,case when s.session_user_id_hash is not null then 'user:'||s.session_user_id_hash
                    when b.identity_count=1 and not b.has_conflict then 'user:'||b.user_id_hash
                    else 'browser:'||s.client_visitor_id end identity_key
                  from session_summary s join browser_identity_stats b using(client_visitor_id)
                ), ranked_sessions as (
                  select s.*,row_number() over(partition by identity_key order by last_activity_at desc,
                    client_visitor_id,client_session_id) identity_rank from session_identity s
                )
                select s.client_visitor_id,s.client_session_id,s.started_at,s.last_activity_at,s.event_count,s.page_views,
                  s.entry_page,l.event_type,l.page_path,l.page_title,c.context->>'countryCode',c.context->>'region',
                  c.context->>'city',c.context->>'browser',c.context->>'operatingSystem',c.context->>'deviceType',
                  c.context->>'language',coalesce(a.actions_json,'[]'),s.identity_rank=1
                from ranked_sessions s join latest_event l using(client_visitor_id,client_session_id)
                  left join visit_context c using(client_visitor_id,client_session_id)
                  left join actions a using(client_visitor_id,client_session_id)
                order by s.last_activity_at desc,s.client_visitor_id
                """;
        List<LiveVisitor> visitors = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, site);
            statement.setInt(2, windowMinutes);
            statement.setInt(3, limit);
            statement.setObject(4, site);
            statement.setObject(5, site);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    Instant startedAt = rows.getTimestamp(3).toInstant();
                    Instant lastActivityAt = rows.getTimestamp(4).toInstant();
                    List<LiveAction> actions;
                    try {
                        actions = mapper.readValue(rows.getString(18), new TypeReference<>() {});
                    } catch (Exception invalidActions) {
                        actions = List.of();
                    }
                    visitors.add(new LiveVisitor(
                            rows.getString(1),
                            rows.getString(2),
                            startedAt,
                            lastActivityAt,
                            rows.getInt(5),
                            rows.getInt(6),
                            rows.getString(7),
                            rows.getString(8),
                            rows.getString(9),
                            rows.getString(10),
                            rows.getString(11),
                            rows.getString(12),
                            rows.getString(13),
                            rows.getString(14),
                            rows.getString(15),
                            rows.getString(16),
                            rows.getString(17),
                            Duration.between(startedAt, lastActivityAt).toMillis(),
                            actions,
                            rows.getBoolean(19)));
                }
            }
            return visitors;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query realtime visitors", error);
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
                "select count(distinct identity_key) from visitor_identity_day_fact where site_id=? and business_date between ? and ?")) {
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

    public record PageTitle(String path, String title, long pageViews) {}

    public record PageFlow(String flow, String path, String title, long sessions) {}

    public record PageTransition(
            int step, String sourcePath, String sourceTitle, String targetPath, String targetTitle, long sessions) {}

    public record UserFlowSamples(
            long totalSessions, boolean hasMore, String nextCursor, List<UserFlowSampleSession> sessions) {}

    public record UserFlowSampleSession(
            String sessionId, Instant startedAt, Instant lastActivityAt, List<UserFlowSamplePage> pages) {}

    public record UserFlowSamplePage(int step, Instant at, String path, String title) {}

    public record Traffic(
            String channel,
            String source,
            String medium,
            String campaign,
            String term,
            String content,
            long sessions) {}

    public record Event(String eventType, long count) {}

    public record VisitorOverview(
            long uniqueVisitors,
            long sessions,
            long newSessions,
            long returningSessions,
            double bounceRate,
            long averageSessionDurationMs) {}

    public record VisitorLog(
            String visitorId,
            Instant startedAt,
            Instant lastActivityAt,
            String entryPage,
            String exitPage,
            int pageViews,
            int events,
            long durationMs,
            boolean bounce,
            String visitorType) {}

    public record VisitorProfile(
            String visitorId,
            Instant firstSeenAt,
            Instant lastSeenAt,
            long lifetimeSessions,
            String identityLinkStatus,
            int linkedBrowserCount,
            long rangeSessions,
            long rangePageViews,
            long rangeEvents,
            long rangeBouncedSessions,
            long averageSessionDurationMs,
            List<VisitorProfileSession> sessions,
            boolean hasMoreSessions,
            String nextSessionsCursor,
            List<VisitorProfileAction> actions,
            boolean hasMoreActions,
            String nextActionsCursor) {}

    public record VisitorProfileHistoryPage(
            List<VisitorProfileSession> sessions,
            String nextSessionsCursor,
            List<VisitorProfileAction> actions,
            String nextActionsCursor) {}

    public record VisitorProfileSession(
            String sessionId,
            Instant startedAt,
            Instant lastActivityAt,
            String entryPage,
            String exitPage,
            int pageViews,
            int events,
            long durationMs,
            boolean bounce,
            String visitorType,
            String browser,
            String operatingSystem,
            String deviceType,
            String language,
            String countryCode,
            String region,
            String city,
            String referrerHost,
            String campaignSource,
            String campaignMedium,
            String campaignName) {}

    public record VisitorProfileAction(Instant at, String eventType, String path, String title, String sessionId) {}

    public record Goal(
            String name, long count, long convertedSessions, java.math.BigDecimal value, double conversionRate) {}

    public record Technology(String dimension, String value, long sessions, long visitors) {}

    public record Location(
            String level,
            String label,
            String countryCode,
            String continentCode,
            String regionCode,
            String region,
            String city,
            String timezone,
            long sessions,
            long visitors) {}

    public record LiveAction(Instant at, String eventType, String path, String title) {}

    public record LiveVisitor(
            String visitorId,
            String sessionId,
            Instant startedAt,
            Instant lastActivityAt,
            int events,
            int pageViews,
            String entryPage,
            String lastEventType,
            String currentPage,
            String currentTitle,
            String countryCode,
            String region,
            String city,
            String browser,
            String operatingSystem,
            String deviceType,
            String language,
            long durationMs,
            List<LiveAction> actions,
            boolean uniqueIdentity) {}
}
