package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.Instant;
import java.time.LocalDate;
import java.util.*;
import javax.sql.DataSource;

/** Executes report queries from session facts when a saved audience segment is selected. */
@ApplicationScoped
public class SegmentedAnalyticsQueryService {
    private static final String EVENT_TIME = "(case when e.occurred_at < e.received_at - interval '24 hours' "
            + "or e.occurred_at > e.received_at + interval '24 hours' then e.received_at else e.occurred_at end)";

    private final DataSource dataSource;
    private final SiteService sites;
    private final SegmentService segments;

    @Inject
    public SegmentedAnalyticsQueryService(DataSource dataSource, SiteService sites, SegmentService segments) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.segments = segments;
    }

    public AnalyticsQueryService.Overview overview(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + " select (select count(*) from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                + " where e.event_type='page_view' and " + eventBusinessDate("e") + " between ? and ?),"
                + "count(distinct visitor_id),count(*),count(*) filter(where is_bounce),coalesce(sum(duration_ms),0) "
                + "from matching_sessions";
        List<Object> after = List.of(context.timezone(), range.from(), range.to());
        return single(context, sql, after, row -> {
            long sessions = row.getLong(3);
            return new AnalyticsQueryService.Overview(
                    range.from(),
                    range.to(),
                    row.getLong(1),
                    row.getLong(2),
                    sessions,
                    ratio(row.getLong(4), sessions),
                    sessions == 0 ? 0 : row.getLong(5) / sessions);
        });
    }

    public List<AnalyticsQueryService.Daily> timeseries(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + ", session_days as (select (started_at at time zone ?)::date business_date,"
                + "count(distinct visitor_id) visitors,count(*) sessions from matching_sessions group by business_date),"
                + " page_days as (select " + eventBusinessDate("e") + " business_date,count(*) page_views "
                + "from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                + " where e.event_type='page_view' and " + eventBusinessDate("e")
                + " between ? and ? group by business_date) "
                + "select d::date,coalesce(p.page_views,0),coalesce(s.visitors,0),coalesce(s.sessions,0) "
                + "from generate_series(?::date,?::date,interval '1 day') d "
                + "left join session_days s on s.business_date=d::date left join page_days p on p.business_date=d::date "
                + "order by d::date";
        List<Object> after = List.of(
                context.timezone(),
                context.timezone(),
                context.timezone(),
                range.from(),
                range.to(),
                range.from(),
                range.to());
        return list(
                context,
                sql,
                after,
                row -> new AnalyticsQueryService.Daily(
                        row.getObject(1, LocalDate.class), row.getLong(2), row.getLong(3), row.getLong(4)));
    }

    public List<AnalyticsQueryService.Page> pages(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + " select e.page_path,count(*) from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                + " where e.event_type='page_view' and e.page_path is not null and " + eventBusinessDate("e")
                + " between ? and ? group by e.page_path order by count(*) desc,e.page_path asc";
        return list(
                context,
                sql,
                List.of(context.timezone(), range.from(), range.to()),
                row -> new AnalyticsQueryService.Page(row.getString(1), row.getLong(2)));
    }

    public List<AnalyticsQueryService.PageTitle> pageTitles(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + " select e.page_path,nullif(e.page_title,''),count(*) from matching_sessions ms "
                + "join raw_event e on " + eventScope("e", "ms")
                + " where e.event_type='page_view' and e.page_path is not null and "
                + eventBusinessDate("e") + " between ? and ? group by e.page_path,e.page_title "
                + "order by count(*) desc,e.page_path,e.page_title limit 100";
        return list(
                context,
                sql,
                List.of(context.timezone(), range.from(), range.to()),
                row -> new AnalyticsQueryService.PageTitle(row.getString(1), row.getString(2), row.getLong(3)));
    }

    public List<AnalyticsQueryService.PageFlow> entryExit(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + ", flows as (select 'entry' flow,entry_page path,entry_page_title title,count(*) sessions "
                + "from matching_sessions where entry_page is not null group by entry_page,entry_page_title "
                + "union all select 'exit' flow,exit_page path,exit_page_title title,count(*) sessions "
                + "from matching_sessions where exit_page is not null group by exit_page,exit_page_title) "
                + "select flow,path,nullif(title,''),sessions from flows order by flow,sessions desc,path limit 200";
        return list(
                context,
                sql,
                List.of(),
                row -> new AnalyticsQueryService.PageFlow(
                        row.getString(1), row.getString(2), row.getString(3), row.getLong(4)));
    }

    public List<AnalyticsQueryService.PageTransition> userFlow(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + ", page_actions as (select ms.id session_id,e.page_path path,nullif(btrim(e.page_title),'') title,"
                + "row_number() over(partition by ms.id order by " + EVENT_TIME
                + ",e.received_at,e.ingest_id) step "
                + "from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                + " where e.event_type='page_view' and e.page_path is not null),"
                + " transitions as (select step,path source_path,title source_title,"
                + "lead(path) over(partition by session_id order by step) target_path,"
                + "lead(title) over(partition by session_id order by step) target_title "
                + "from page_actions),"
                + " grouped as (select step,source_path,source_title,target_path,target_title,count(*) sessions "
                + "from transitions where step<=5 group by step,source_path,source_title,target_path,target_title),"
                + " ranked as (select *,row_number() over(partition by step order by sessions desc,"
                + "source_path,target_path nulls last) rank from grouped) "
                + "select step,source_path,source_title,target_path,target_title,sessions from ranked "
                + "where rank<=100 order by step,rank";
        return list(
                context,
                sql,
                List.of(),
                row -> new AnalyticsQueryService.PageTransition(
                        row.getInt(1),
                        row.getString(2),
                        row.getString(3),
                        row.getString(4),
                        row.getString(5),
                        row.getLong(6)));
    }

    public AnalyticsQueryService.UserFlowSamples userFlowSamples(
            UUID siteId,
            AnalyticsQueryService.Range range,
            UUID segmentId,
            int step,
            String sourcePath,
            String sourceTitle,
            String targetPath,
            String targetTitle,
            String cursorToken) {
        QueryContext context = context(siteId, range, segmentId);
        UserFlowCursor cursor = UserFlowCursor.decode(cursorToken);
        final int sampleLimit = 20;
        String sql = cte(context)
                + ", page_actions as (select ms.id session_id,e.page_path path,nullif(btrim(e.page_title),'') title,"
                + EVENT_TIME + " event_at,row_number() over(partition by ms.id order by " + EVENT_TIME
                + ",e.received_at,e.ingest_id) step from matching_sessions ms join raw_event e on "
                + eventScope("e", "ms")
                + " where e.event_type='page_view' and e.page_path is not null),"
                + " transitions as (select session_id,step,path source_path,title source_title,"
                + "lead(path) over(partition by session_id order by step) target_path,"
                + "lead(title) over(partition by session_id order by step) target_title from page_actions),"
                + " matched_transitions as (select distinct session_id from transitions where step=? "
                + "and source_path=? and (?::text is null or source_title=?) and target_path is not distinct from ? "
                + "and (?::text is null or target_title=?)),"
                + " sample_sessions as (select ms.id,ms.client_session_id,ms.started_at,ms.last_activity_at "
                + "from matching_sessions ms join matched_transitions mt on mt.session_id=ms.id "
                + (cursor == null ? "" : "where (ms.started_at < ? or (ms.started_at = ? and ms.id < ?::uuid)) ")
                + "order by ms.started_at desc,ms.id desc limit ?),"
                + " report_total as (select count(*) total from matched_transitions) "
                + "select ss.id,ss.client_session_id,ss.started_at,ss.last_activity_at,pa.step,pa.event_at,pa.path,"
                + "pa.title,rt.total from report_total rt left join sample_sessions ss on true "
                + "left join page_actions pa on pa.session_id=ss.id and pa.step<=6 "
                + "order by ss.started_at desc,ss.id desc,pa.step";

        List<Object> parameters = new ArrayList<>(
                Arrays.asList(step, sourcePath, sourceTitle, sourceTitle, targetPath, targetTitle, targetTitle));
        if (cursor != null) {
            Timestamp timestamp = Timestamp.from(cursor.startedAt());
            parameters.add(timestamp);
            parameters.add(timestamp);
            parameters.add(cursor.sessionKey());
        }
        parameters.add(sampleLimit + 1);
        Map<UUID, UserFlowSampleBuilder> grouped = new LinkedHashMap<>();
        long[] total = {0};
        list(context, sql, parameters, row -> {
            total[0] = row.getLong(9);
            UUID sessionKey = row.getObject(1, UUID.class);
            if (sessionKey == null) return null;
            String sessionId = row.getString(2);
            UserFlowSampleBuilder sample = grouped.computeIfAbsent(
                    sessionKey,
                    ignored ->
                            new UserFlowSampleBuilder(sessionKey, sessionId, rowInstant(row, 3), rowInstant(row, 4)));
            if (row.getObject(5) != null) {
                sample.pages.add(new AnalyticsQueryService.UserFlowSamplePage(
                        row.getInt(5), rowInstant(row, 6), row.getString(7), row.getString(8)));
            }
            return null;
        });
        List<UserFlowSampleBuilder> page = new ArrayList<>(grouped.values());
        boolean hasMore = page.size() > sampleLimit;
        if (hasMore) page.remove(page.size() - 1);
        List<AnalyticsQueryService.UserFlowSampleSession> sessions = page.stream()
                .map(sample -> new AnalyticsQueryService.UserFlowSampleSession(
                        sample.clientSessionId, sample.startedAt, sample.lastActivityAt, List.copyOf(sample.pages)))
                .toList();
        String nextCursor = hasMore ? UserFlowCursor.encode(page.get(page.size() - 1)) : null;
        return new AnalyticsQueryService.UserFlowSamples(total[0], hasMore, nextCursor, sessions);
    }

    private record UserFlowCursor(Instant startedAt, UUID sessionKey) {
        private static String encode(UserFlowSampleBuilder sample) {
            String raw = sample.startedAt + "|" + sample.sessionKey;
            return Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString(raw.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }

        private static UserFlowCursor decode(String token) {
            if (token == null) return null;
            try {
                String raw = new String(Base64.getUrlDecoder().decode(token), java.nio.charset.StandardCharsets.UTF_8);
                String[] parts = raw.split("\\|", -1);
                if (parts.length != 2) throw new IllegalArgumentException("Invalid cursor payload");
                return new UserFlowCursor(Instant.parse(parts[0]), UUID.fromString(parts[1]));
            } catch (RuntimeException error) {
                throw new ControlPlaneException(400, "INVALID_USER_FLOW_CURSOR", "User-flow cursor is invalid");
            }
        }
    }

    private static Instant rowInstant(ResultSet row, int column) {
        try {
            return row.getTimestamp(column).toInstant();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read user-flow sample time", error);
        }
    }

    private static final class UserFlowSampleBuilder {
        private final UUID sessionKey;
        private final String clientSessionId;
        private final Instant startedAt;
        private final Instant lastActivityAt;
        private final List<AnalyticsQueryService.UserFlowSamplePage> pages = new ArrayList<>();

        private UserFlowSampleBuilder(
                UUID sessionKey, String clientSessionId, Instant startedAt, Instant lastActivityAt) {
            this.sessionKey = sessionKey;
            this.clientSessionId = clientSessionId;
            this.startedAt = startedAt;
            this.lastActivityAt = lastActivityAt;
        }
    }

    public List<AnalyticsQueryService.Traffic> traffic(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + ", classified as (select ms.initial_referrer_host,ms.initial_utm_source,ms.initial_utm_medium,"
                + "ms.initial_utm_campaign,ms.initial_utm_term,ms.initial_utm_content,"
                + AcquisitionClassifier.channelSql("ms")
                + " channel from matching_sessions ms), traffic_rows as (select channel,"
                + "nullif(case when channel='campaign' then initial_utm_source when channel='direct' then null else initial_referrer_host end,'') source,"
                + "nullif(initial_utm_medium,'') medium,nullif(initial_utm_campaign,'') campaign,"
                + "nullif(initial_utm_term,'') term,nullif(initial_utm_content,'') content from classified) "
                + "select channel,source,medium,campaign,term,content,count(*) from traffic_rows "
                + "group by channel,source,medium,campaign,term,content order by count(*) desc,channel asc";
        return list(
                context,
                sql,
                List.of(),
                row -> new AnalyticsQueryService.Traffic(
                        row.getString(1),
                        row.getString(2),
                        row.getString(3),
                        row.getString(4),
                        row.getString(5),
                        row.getString(6),
                        row.getLong(7)));
    }

    public List<AnalyticsQueryService.Event> events(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + " select e.event_type,count(*) from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                + " where e.event_type<>'web_vital' and " + eventBusinessDate("e")
                + " between ? and ? group by e.event_type "
                + "order by count(*) desc,e.event_type asc";
        return list(
                context,
                sql,
                List.of(context.timezone(), range.from(), range.to()),
                row -> new AnalyticsQueryService.Event(row.getString(1), row.getLong(2)));
    }

    public SiteSearchReport siteSearch(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        // A session can span midnight; retain the preceding local day when selecting sessions,
        // then apply the requested range to the search event's own business date below.
        QueryContext candidateSessions = new QueryContext(
                context.siteId(),
                new AnalyticsQueryService.Range(range.from().minusDays(1), range.to()),
                context.timezone(),
                context.filter());
        String sql = cte(candidateSessions)
                + ", search_events as (select e.client_visitor_id visitor_id,e.client_session_id session_id,"
                + "coalesce(nullif(btrim(e.event_data->'data'->>'keyword'),''),"
                + "nullif(btrim(e.event_data->>'name'),'')) keyword,"
                + "coalesce(nullif(btrim(e.event_data->'data'->>'searchCategory'),''),"
                + "nullif(btrim(e.event_data->'data'->>'category'),''),"
                + "nullif(btrim(e.event_data->>'action'),'')) category,"
                + "case when e.event_data->'data'->>'resultsCount' ~ '^[0-9]{1,10}$' then "
                + "case when (e.event_data->'data'->>'resultsCount')::bigint<=1000000000 "
                + "then (e.event_data->'data'->>'resultsCount')::bigint end end results_count "
                + "from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                + " where e.event_type='site_search' and " + eventBusinessDate("e") + " between ? and ? "
                + "and coalesce(nullif(btrim(e.event_data->'data'->>'keyword'),''),"
                + "nullif(btrim(e.event_data->>'name'),'')) is not null),"
                + "grouped as (select grouping(keyword,category)=3 total_row,keyword,category,count(*) searches,"
                + "count(distinct visitor_id) visitors,count(distinct session_id) sessions,"
                + "count(*) filter(where results_count=0) zero_results,count(results_count) measured_results,"
                + "avg(results_count)::double precision average_results from search_events "
                + "group by grouping sets ((),(keyword,category))) "
                + "select total_row,keyword,category,searches,visitors,sessions,zero_results,measured_results,"
                + "average_results from grouped order by total_row desc,searches desc,keyword asc,category asc limit 101";
        SiteSearchReport summary = null;
        List<SiteSearchTerm> terms = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            bindExtras(
                    statement,
                    bindBase(statement, candidateSessions),
                    List.of(context.timezone(), range.from(), range.to()));
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    boolean total = rows.getBoolean(1);
                    String keyword = rows.getString(2);
                    String category = rows.getString(3);
                    long searches = rows.getLong(4);
                    long visitors = rows.getLong(5);
                    long sessions = rows.getLong(6);
                    long zeroResults = rows.getLong(7);
                    long measuredResults = rows.getLong(8);
                    double averageResults = rows.getDouble(9);
                    Double average = rows.wasNull() ? null : averageResults;
                    if (total) {
                        summary = new SiteSearchReport(
                                searches, visitors, sessions, zeroResults, measuredResults, average, List.of());
                    } else {
                        terms.add(new SiteSearchTerm(
                                keyword,
                                category,
                                searches,
                                visitors,
                                sessions,
                                zeroResults,
                                measuredResults,
                                average));
                    }
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query site search analytics", error);
        }
        if (summary == null) throw new IllegalStateException("Site search report did not return a summary row");
        return new SiteSearchReport(
                summary.searches(),
                summary.uniqueVisitors(),
                summary.sessions(),
                summary.zeroResultSearches(),
                summary.measuredResultSearches(),
                summary.averageResultsCount(),
                List.copyOf(terms));
    }

    public ContentReport content(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        QueryContext candidateSessions = new QueryContext(
                context.siteId(),
                new AnalyticsQueryService.Range(range.from().minusDays(1), range.to()),
                context.timezone(),
                context.filter());
        String contentName = "coalesce(nullif(btrim(e.event_data->'data'->>'contentName'),''),"
                + "nullif(btrim(e.event_data->>'name'),''))";
        String sql = cte(candidateSessions)
                + ", content_events as (select e.client_visitor_id visitor_id,e.client_session_id session_id,"
                + contentName + " content_name,"
                + "nullif(btrim(e.event_data->'data'->>'contentPiece'),'') content_piece,"
                + "nullif(btrim(regexp_replace(e.event_data->'data'->>'contentTarget','[?#].*$','')),'') content_target,"
                + "e.event_type "
                + "from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                + " where e.event_type in ('content_impression','content_interaction') and "
                + eventBusinessDate("e") + " between ? and ? and " + contentName + " is not null),"
                + "grouped as (select grouping(content_name,content_piece,content_target)=7 total_row,"
                + "content_name,content_piece,content_target,"
                + "count(*) filter(where event_type='content_impression') impressions,"
                + "count(*) filter(where event_type='content_interaction') interactions,"
                + "count(distinct visitor_id) visitors,count(distinct session_id) sessions "
                + "from content_events group by grouping sets ((),(content_name,content_piece,content_target))) "
                + "select total_row,content_name,content_piece,content_target,impressions,interactions,visitors,sessions "
                + "from grouped order by total_row desc,impressions desc,interactions desc,content_name asc,"
                + "content_piece asc,content_target asc limit 101";
        ContentReport summary = null;
        List<ContentEntry> entries = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            bindExtras(
                    statement,
                    bindBase(statement, candidateSessions),
                    List.of(context.timezone(), range.from(), range.to()));
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    boolean total = rows.getBoolean(1);
                    String name = rows.getString(2);
                    String piece = rows.getString(3);
                    String target = rows.getString(4);
                    long impressions = rows.getLong(5);
                    long interactions = rows.getLong(6);
                    long visitors = rows.getLong(7);
                    long sessions = rows.getLong(8);
                    double interactionRate = impressions == 0 ? 0d : (double) interactions / impressions;
                    if (total) {
                        summary = new ContentReport(
                                impressions, interactions, visitors, sessions, interactionRate, List.of());
                    } else {
                        entries.add(new ContentEntry(
                                name, piece, target, impressions, interactions, visitors, sessions, interactionRate));
                    }
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query content analytics", error);
        }
        if (summary == null) throw new IllegalStateException("Content report did not return a summary row");
        return new ContentReport(
                summary.impressions(),
                summary.interactions(),
                summary.uniqueVisitors(),
                summary.sessions(),
                summary.interactionRate(),
                List.copyOf(entries));
    }

    public WebVitalsReport webVitals(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        QueryContext candidateSessions = new QueryContext(
                context.siteId(),
                new AnalyticsQueryService.Range(range.from().minusDays(1), range.to()),
                context.timezone(),
                context.filter());
        String metricValue = "case when e.event_data->'data'->>'value' ~ '^[0-9]{1,10}(\\.[0-9]{1,6})?$' "
                + "then (e.event_data->'data'->>'value')::double precision end";
        String sql = cte(candidateSessions)
                + ", selected_events as (select e.client_visitor_id visitor_id,e.client_session_id session_id,"
                + "e.page_path,nullif(btrim(e.event_data->'data'->>'metric'),'') metric,"
                + "nullif(btrim(e.event_data->'data'->>'metricId'),'') metric_id," + metricValue + " metric_value,"
                + EVENT_TIME + " event_time,e.received_at,e.ingest_id "
                + "from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                + " where e.event_type='web_vital' and " + eventBusinessDate("e") + " between ? and ?),"
                + "valid_events as (select * from selected_events where metric in ('LCP','INP','CLS') "
                + "and metric_id is not null and length(metric_id) between 1 and 128 "
                + "and metric_value between 0 and 1000000000),"
                + "latest_events as (select distinct on (visitor_id,session_id,metric,metric_id) "
                + "visitor_id,session_id,page_path,metric,metric_id,metric_value from valid_events "
                + "order by visitor_id,session_id,metric,metric_id,event_time desc,received_at desc,ingest_id desc),"
                + "rated_events as (select *,case when (metric='LCP' and metric_value<=2500) "
                + "or (metric='INP' and metric_value<=200) or (metric='CLS' and metric_value<=0.1) then 'good' "
                + "when (metric='LCP' and metric_value<=4000) or (metric='INP' and metric_value<=500) "
                + "or (metric='CLS' and metric_value<=0.25) then 'needs_improvement' else 'poor' end rating "
                + "from latest_events),"
                + "grouped as (select grouping(metric,page_path)=1 total_row,metric,page_path,count(*) samples,"
                + "count(distinct visitor_id) visitors,count(distinct session_id) sessions,"
                + "(percentile_cont(0.75) within group (order by metric_value))::double precision p75,"
                + "count(*) filter(where rating='good') good,count(*) filter(where rating='needs_improvement') needs_improvement,"
                + "count(*) filter(where rating='poor') poor from rated_events "
                + "group by grouping sets ((metric),(metric,page_path))),"
                + "ranked as (select *,row_number() over(partition by metric,total_row "
                + "order by samples desc,page_path asc nulls last) row_number from grouped) "
                + "select total_row,metric,page_path,samples,visitors,sessions,p75,good,needs_improvement,poor "
                + "from ranked where total_row or row_number<=100 order by total_row desc,"
                + "case metric when 'LCP' then 1 when 'INP' then 2 else 3 end,samples desc,page_path asc nulls last";
        List<WebVitalPage> pages = new ArrayList<>();
        List<WebVitalSummary> metrics = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            bindExtras(
                    statement,
                    bindBase(statement, candidateSessions),
                    List.of(context.timezone(), range.from(), range.to()));
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    boolean total = rows.getBoolean(1);
                    String metric = rows.getString(2);
                    String pagePath = rows.getString(3);
                    long samples = rows.getLong(4);
                    long visitors = rows.getLong(5);
                    long sessions = rows.getLong(6);
                    double p75 = rows.getDouble(7);
                    long good = rows.getLong(8);
                    long needsImprovement = rows.getLong(9);
                    long poor = rows.getLong(10);
                    if (total) {
                        metrics.add(new WebVitalSummary(
                                metric, samples, visitors, sessions, p75, good, needsImprovement, poor));
                    } else {
                        pages.add(new WebVitalPage(
                                metric, pagePath, samples, visitors, sessions, p75, good, needsImprovement, poor));
                    }
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query Web Vitals analytics", error);
        }
        return new WebVitalsReport(List.copyOf(metrics), List.copyOf(pages));
    }

    public AnalyticsQueryService.VisitorOverview visitors(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + " select count(distinct visitor_id),count(*),count(*) filter(where visitor_type='new'),"
                + "count(*) filter(where visitor_type='returning'),count(*) filter(where is_bounce),coalesce(sum(duration_ms),0) "
                + "from matching_sessions";
        return single(context, sql, List.of(), row -> {
            long sessions = row.getLong(2);
            return new AnalyticsQueryService.VisitorOverview(
                    row.getLong(1),
                    sessions,
                    row.getLong(3),
                    row.getLong(4),
                    ratio(row.getLong(5), sessions),
                    sessions == 0 ? 0 : row.getLong(6) / sessions);
        });
    }

    public List<AnalyticsQueryService.VisitorLog> visitorLog(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId, int requestedLimit) {
        QueryContext context = context(siteId, range, segmentId);
        int limit = Math.max(1, Math.min(requestedLimit, 200));
        String sql = cte(context)
                + " select client_visitor_id,started_at,last_activity_at,entry_page,exit_page,page_view_count,event_count,"
                + "duration_ms,is_bounce,visitor_type from matching_sessions order by started_at desc limit ?";
        return list(
                context,
                sql,
                List.of(limit),
                row -> new AnalyticsQueryService.VisitorLog(
                        row.getString(1),
                        row.getTimestamp(2).toInstant(),
                        row.getTimestamp(3).toInstant(),
                        row.getString(4),
                        row.getString(5),
                        row.getInt(6),
                        row.getInt(7),
                        row.getLong(8),
                        row.getBoolean(9),
                        row.getString(10)));
    }

    public AnalyticsQueryService.VisitorProfile visitorProfile(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId, String visitorId) {
        if (visitorId == null || visitorId.isBlank() || visitorId.length() > 64)
            throw new ControlPlaneException(400, "INVALID_VISITOR_ID", "Visitor ID is invalid");

        Instant firstSeenAt;
        Instant lastSeenAt;
        long lifetimeSessions;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select first_seen_at,last_seen_at,session_count from analytics_visitor where site_id=? and client_visitor_id=?")) {
            statement.setObject(1, siteId);
            statement.setString(2, visitorId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) return null;
                firstSeenAt = row.getTimestamp(1).toInstant();
                lastSeenAt = row.getTimestamp(2).toInstant();
                lifetimeSessions = row.getLong(3);
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query visitor profile", error);
        }

        QueryContext context = context(siteId, range, segmentId);
        long[] totals = single(
                context,
                cte(context)
                        + " select count(*),coalesce(sum(page_view_count),0),coalesce(sum(event_count),0),"
                        + "count(*) filter(where is_bounce),coalesce(avg(duration_ms),0) from matching_sessions "
                        + "where client_visitor_id=?",
                List.of(visitorId),
                row -> new long[] {row.getLong(1), row.getLong(2), row.getLong(3), row.getLong(4), row.getLong(5)});

        final int sessionLimit = 50;
        List<AnalyticsQueryService.VisitorProfileSession> sessions = list(
                context,
                cte(context)
                        + " select client_session_id,started_at,last_activity_at,entry_page,exit_page,page_view_count,"
                        + "event_count,duration_ms,is_bounce,visitor_type,browser,operating_system,device_type,language,"
                        + "country_code,region_name,city,initial_referrer_host,initial_utm_source,initial_utm_medium,"
                        + "initial_utm_campaign from matching_sessions where client_visitor_id=? "
                        + "order by started_at desc,client_session_id limit ?",
                List.of(visitorId, sessionLimit + 1),
                row -> new AnalyticsQueryService.VisitorProfileSession(
                        row.getString(1),
                        row.getTimestamp(2).toInstant(),
                        row.getTimestamp(3).toInstant(),
                        row.getString(4),
                        row.getString(5),
                        row.getInt(6),
                        row.getInt(7),
                        row.getLong(8),
                        row.getBoolean(9),
                        row.getString(10),
                        row.getString(11),
                        row.getString(12),
                        row.getString(13),
                        row.getString(14),
                        row.getString(15),
                        row.getString(16),
                        row.getString(17),
                        row.getString(18),
                        row.getString(19),
                        row.getString(20),
                        row.getString(21)));
        boolean hasMoreSessions = sessions.size() > sessionLimit;
        if (hasMoreSessions) sessions.remove(sessions.size() - 1);
        String nextSessionsCursor = hasMoreSessions
                ? VisitorHistoryCursor.encode(
                        "s",
                        visitorId,
                        sessions.get(sessions.size() - 1).startedAt(),
                        sessions.get(sessions.size() - 1).sessionId())
                : null;

        final int actionLimit = 100;
        String actionsSql = cte(context)
                + ", visitor_actions as (select " + EVENT_TIME
                + " action_at,e.ingest_id,e.event_type,e.page_path,e.page_title,ms.client_session_id "
                + "from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                + " where ms.client_visitor_id=? and e.event_type<>'web_vital') "
                + "select action_at,event_type,page_path,page_title,client_session_id,ingest_id from visitor_actions "
                + "order by action_at desc,ingest_id desc limit ?";
        List<VisitorProfileActionCursor> actionRows = list(
                context,
                actionsSql,
                List.of(visitorId, actionLimit + 1),
                row -> new VisitorProfileActionCursor(
                        new AnalyticsQueryService.VisitorProfileAction(
                                row.getTimestamp(1).toInstant(),
                                row.getString(2),
                                row.getString(3),
                                row.getString(4),
                                row.getString(5)),
                        row.getString(6)));
        boolean hasMoreActions = actionRows.size() > actionLimit;
        if (hasMoreActions) actionRows.remove(actionRows.size() - 1);
        List<AnalyticsQueryService.VisitorProfileAction> actions =
                actionRows.stream().map(VisitorProfileActionCursor::action).toList();
        String nextActionsCursor = hasMoreActions
                ? VisitorHistoryCursor.encode(
                        "a",
                        visitorId,
                        actionRows.get(actionRows.size() - 1).action().at(),
                        actionRows.get(actionRows.size() - 1).ingestId())
                : null;

        return new AnalyticsQueryService.VisitorProfile(
                visitorId,
                firstSeenAt,
                lastSeenAt,
                lifetimeSessions,
                totals[0],
                totals[1],
                totals[2],
                totals[3],
                totals[0] == 0 ? 0 : totals[4],
                List.copyOf(sessions),
                hasMoreSessions,
                nextSessionsCursor,
                List.copyOf(actions),
                hasMoreActions,
                nextActionsCursor);
    }

    public AnalyticsQueryService.VisitorProfileHistoryPage visitorProfileHistory(
            UUID siteId,
            AnalyticsQueryService.Range range,
            UUID segmentId,
            String visitorId,
            String sessionsCursorToken,
            String actionsCursorToken) {
        if (visitorId == null || visitorId.isBlank() || visitorId.length() > 64)
            throw new ControlPlaneException(400, "INVALID_VISITOR_ID", "Visitor ID is invalid");
        if (!visitorExists(siteId, visitorId)) return null;
        QueryContext context = context(siteId, range, segmentId);
        final int sessionLimit = 50;
        boolean includeSessions = sessionsCursorToken != null || actionsCursorToken == null;
        boolean includeActions = actionsCursorToken != null || sessionsCursorToken == null;
        List<AnalyticsQueryService.VisitorProfileSession> sessions = new ArrayList<>();
        String nextSessionsCursor = null;
        if (includeSessions) {
            VisitorHistoryCursor sessionCursor = VisitorHistoryCursor.decode(sessionsCursorToken, "s", visitorId);
            List<Object> sessionParameters = new ArrayList<>();
            sessionParameters.add(visitorId);
            String sessionCursorPredicate = "";
            if (sessionCursor != null) {
                sessionCursorPredicate = " and (started_at<? or (started_at=? and client_session_id>?))";
                Timestamp cursorTime = Timestamp.from(sessionCursor.at());
                sessionParameters.add(cursorTime);
                sessionParameters.add(cursorTime);
                sessionParameters.add(sessionCursor.rowId());
            }
            sessionParameters.add(sessionLimit + 1);
            sessions = list(
                    context,
                    cte(context)
                            + " select client_session_id,started_at,last_activity_at,entry_page,exit_page,page_view_count,"
                            + "event_count,duration_ms,is_bounce,visitor_type,browser,operating_system,device_type,language,"
                            + "country_code,region_name,city,initial_referrer_host,initial_utm_source,initial_utm_medium,"
                            + "initial_utm_campaign from matching_sessions where client_visitor_id=?"
                            + sessionCursorPredicate
                            + " order by started_at desc,client_session_id limit ?",
                    sessionParameters,
                    SegmentedAnalyticsQueryService::mapVisitorProfileSession);
            boolean hasMoreSessions = sessions.size() > sessionLimit;
            if (hasMoreSessions) sessions.remove(sessions.size() - 1);
            if (hasMoreSessions)
                nextSessionsCursor = VisitorHistoryCursor.encode(
                        "s",
                        visitorId,
                        sessions.get(sessions.size() - 1).startedAt(),
                        sessions.get(sessions.size() - 1).sessionId());
        }

        List<VisitorProfileActionCursor> actionRows = new ArrayList<>();
        String nextActionsCursor = null;
        if (includeActions) {
            VisitorHistoryCursor actionCursor = VisitorHistoryCursor.decode(actionsCursorToken, "a", visitorId);
            List<Object> actionParameters = new ArrayList<>();
            actionParameters.add(visitorId);
            String actionCursorPredicate = "";
            if (actionCursor != null) {
                actionCursorPredicate = " and (" + EVENT_TIME + "<? or (" + EVENT_TIME + "=? and e.ingest_id<?))";
                Timestamp cursorTime = Timestamp.from(actionCursor.at());
                actionParameters.add(cursorTime);
                actionParameters.add(cursorTime);
                actionParameters.add(UUID.fromString(actionCursor.rowId()));
            }
            actionParameters.add(101);
            String actionsSql = cte(context)
                    + ", visitor_actions as (select " + EVENT_TIME
                    + " action_at,e.ingest_id,e.event_type,e.page_path,e.page_title,ms.client_session_id "
                    + "from matching_sessions ms join raw_event e on " + eventScope("e", "ms")
                    + " where ms.client_visitor_id=? and e.event_type<>'web_vital'" + actionCursorPredicate + ") "
                    + "select action_at,event_type,page_path,page_title,client_session_id,ingest_id from visitor_actions "
                    + "order by action_at desc,ingest_id desc limit ?";
            actionRows = list(
                    context,
                    actionsSql,
                    actionParameters,
                    row -> new VisitorProfileActionCursor(
                            new AnalyticsQueryService.VisitorProfileAction(
                                    row.getTimestamp(1).toInstant(),
                                    row.getString(2),
                                    row.getString(3),
                                    row.getString(4),
                                    row.getString(5)),
                            row.getString(6)));
            boolean hasMoreActions = actionRows.size() > 100;
            if (hasMoreActions) actionRows.remove(actionRows.size() - 1);
            if (hasMoreActions)
                nextActionsCursor = VisitorHistoryCursor.encode(
                        "a",
                        visitorId,
                        actionRows.get(actionRows.size() - 1).action().at(),
                        actionRows.get(actionRows.size() - 1).ingestId());
        }
        List<AnalyticsQueryService.VisitorProfileAction> actions =
                actionRows.stream().map(VisitorProfileActionCursor::action).toList();
        return new AnalyticsQueryService.VisitorProfileHistoryPage(
                List.copyOf(sessions), nextSessionsCursor, List.copyOf(actions), nextActionsCursor);
    }

    private boolean visitorExists(UUID siteId, String visitorId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select 1 from analytics_visitor where site_id=? and client_visitor_id=?")) {
            statement.setObject(1, siteId);
            statement.setString(2, visitorId);
            try (ResultSet row = statement.executeQuery()) {
                return row.next();
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not verify visitor profile", error);
        }
    }

    private static AnalyticsQueryService.VisitorProfileSession mapVisitorProfileSession(ResultSet row)
            throws SQLException {
        return new AnalyticsQueryService.VisitorProfileSession(
                row.getString(1),
                row.getTimestamp(2).toInstant(),
                row.getTimestamp(3).toInstant(),
                row.getString(4),
                row.getString(5),
                row.getInt(6),
                row.getInt(7),
                row.getLong(8),
                row.getBoolean(9),
                row.getString(10),
                row.getString(11),
                row.getString(12),
                row.getString(13),
                row.getString(14),
                row.getString(15),
                row.getString(16),
                row.getString(17),
                row.getString(18),
                row.getString(19),
                row.getString(20),
                row.getString(21));
    }

    public List<AnalyticsQueryService.Goal> goals(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + ", goal_hits as (select g.id,g.name,g.fixed_value,ms.id session_id from matching_sessions ms "
                + "join raw_event e on " + eventScope("e", "ms")
                + " join goal_definition g on g.site_id=ms.site_id and g.enabled "
                + "where ((g.trigger_type='event' and e.event_type=g.event_type and (g.event_name is null "
                + "or coalesce(nullif(e.event_data->>'name',''),nullif(e.event_data->'data'->>'name',''))=g.event_name)) "
                + "or (g.trigger_type='page_view' and e.event_type='page_view' and "
                + "((g.path_match_mode='exact' and e.page_path=g.path_pattern) or "
                + "(g.path_match_mode='contains' and position(g.path_pattern in coalesce(e.page_path,''))>0)))) "
                + "and " + eventBusinessDate("e") + " between ? and ?), session_total as "
                + "(select count(*) sessions from matching_sessions) "
                + "select h.name,count(*),count(distinct h.session_id),coalesce(sum(h.fixed_value),0),"
                + "case when t.sessions=0 then 0 else count(distinct h.session_id)::double precision/t.sessions end "
                + "from goal_hits h cross join session_total t group by h.id,h.name,t.sessions "
                + "order by count(*) desc,h.name asc";
        return list(
                context,
                sql,
                List.of(context.timezone(), range.from(), range.to()),
                row -> new AnalyticsQueryService.Goal(
                        row.getString(1), row.getLong(2), row.getLong(3), row.getBigDecimal(4), row.getDouble(5)));
    }

    public List<AnalyticsQueryService.Technology> technology(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + ", dimension_rows as (select ms.id,ms.visitor_id,d.dimension,d.value "
                + "from matching_sessions ms cross join lateral (values "
                + "('Browser',coalesce(nullif(ms.browser,''),'Unknown')),"
                + "('Browser version',case when nullif(ms.browser,'') is null then 'Unknown' "
                + "else ms.browser || ' ' || coalesce(nullif(ms.browser_version,''),'Unknown') end),"
                + "('Operating system',coalesce(nullif(ms.operating_system,''),'Unknown')),"
                + "('OS version',case when nullif(ms.operating_system,'') is null then 'Unknown' "
                + "else ms.operating_system || ' ' || coalesce(nullif(ms.operating_system_version,''),'Unknown') end),"
                + "('Device type',coalesce(nullif(ms.device_type,''),'Unknown')),"
                + "('Language',coalesce(nullif(ms.language,''),'Unknown')),"
                + "('Screen size',case when ms.screen_width is not null and ms.screen_height is not null "
                + "then ms.screen_width::text || ' × ' || ms.screen_height::text || ' px' else 'Unknown' end),"
                + "('Viewport size',case when ms.viewport_width is not null and ms.viewport_height is not null "
                + "then ms.viewport_width::text || ' × ' || ms.viewport_height::text || ' px' else 'Unknown' end),"
                + "('Display scale',case when ms.pixel_ratio is not null "
                + "then ms.pixel_ratio::text || '×' else 'Unknown' end)"
                + ") d(dimension,value)) select dimension,value,count(*),count(distinct visitor_id) "
                + "from dimension_rows group by dimension,value order by case dimension "
                + "when 'Browser' then 1 when 'Browser version' then 2 when 'Operating system' then 3 "
                + "when 'OS version' then 4 when 'Device type' then 5 when 'Language' then 6 "
                + "when 'Screen size' then 7 when 'Viewport size' then 8 else 9 end,count(*) desc,value";
        return list(
                context,
                sql,
                List.of(),
                row -> new AnalyticsQueryService.Technology(
                        row.getString(1), row.getString(2), row.getLong(3), row.getLong(4)));
    }

    public List<AnalyticsQueryService.Location> locations(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        QueryContext context = context(siteId, range, segmentId);
        String sql = cte(context)
                + ", location_rows as ("
                + "select 'country' level,country_code::text country_code,max(continent_code::text) continent_code,"
                + "null::text region_code,null::text region,null::text city,null::text timezone,count(*) sessions,"
                + "count(distinct visitor_id) visitors from matching_sessions where country_code is not null "
                + "group by country_code union all "
                + "select 'continent',null::text,continent_code::text,null::text,null::text,null::text,null::text,"
                + "count(*),count(distinct visitor_id) from matching_sessions where continent_code is not null "
                + "group by continent_code union all "
                + "select 'region',country_code::text,max(continent_code::text),max(region_code::text),max(region_name),null::text,"
                + "null::text,count(*),count(distinct visitor_id) from matching_sessions where country_code is not null "
                + "and (region_code is not null or region_name is not null) "
                + "group by country_code,coalesce(region_code::text,region_name) union all "
                + "select 'city',country_code::text,max(continent_code::text),max(region_code::text),max(region_name),city,"
                + "max(geo_timezone),count(*),count(distinct visitor_id) from matching_sessions where country_code is not null "
                + "and city is not null group by country_code,coalesce(region_code::text,region_name),city) "
                + "select level,country_code,continent_code,region_code,region,city,timezone,sessions,visitors "
                + "from location_rows order by case level when 'country' then 1 when 'continent' then 2 "
                + "when 'region' then 3 else 4 end,sessions desc,country_code nulls last,region nulls last,city nulls last";
        return list(context, sql, List.of(), row -> {
            String level = row.getString(1);
            String country = row.getString(2);
            String continent = row.getString(3);
            String regionCode = row.getString(4);
            String region = row.getString(5);
            String city = row.getString(6);
            String timezone = row.getString(7);
            String label =
                    switch (level) {
                        case "country" -> countryLabel(country);
                        case "continent" -> continentLabel(continent);
                        case "region" -> String.join(
                                " · ", nonEmpty(region == null ? regionCode : region, countryLabel(country)));
                        default -> String.join(
                                " · ", nonEmpty(city, region == null ? regionCode : region, countryLabel(country)));
                    };
            return new AnalyticsQueryService.Location(
                    level,
                    label,
                    country,
                    continent,
                    regionCode,
                    region,
                    city,
                    timezone,
                    row.getLong(8),
                    row.getLong(9));
        });
    }

    private static List<String> nonEmpty(String... values) {
        return Arrays.stream(values)
                .filter(value -> value != null && !value.isBlank())
                .toList();
    }

    private static String countryLabel(String code) {
        if (code == null) return "Unknown";
        String name = new Locale.Builder().setRegion(code).build().getDisplayCountry(Locale.ENGLISH);
        return name.isBlank() ? code : name;
    }

    private static String continentLabel(String code) {
        return switch (code == null ? "" : code) {
            case "AF" -> "Africa";
            case "AN" -> "Antarctica";
            case "AS" -> "Asia";
            case "EU" -> "Europe";
            case "NA" -> "North America";
            case "OC" -> "Oceania";
            case "SA" -> "South America";
            default -> "Unknown";
        };
    }

    private QueryContext context(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        Site site = sites.site(siteId);
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        return new QueryContext(siteId, range, site.timezone, filter);
    }

    private static String cte(QueryContext context) {
        return "with matching_sessions as (select s.id,s.site_id,s.visitor_id,v.client_visitor_id,s.client_session_id,"
                + "s.started_at,s.last_activity_at,s.page_view_count,s.event_count,s.duration_ms,s.is_bounce,s.visitor_type,"
                + "s.entry_page,s.exit_page,s.entry_page_title,s.exit_page_title,s.initial_referrer_host,s.initial_page_host,s.initial_utm_source,"
                + "s.initial_utm_medium,s.initial_utm_campaign,s.initial_utm_term,s.initial_utm_content,s.browser,s.browser_version,s.operating_system,"
                + "s.operating_system_version,s.device_type,s.language,s.screen_width,s.screen_height,"
                + "s.viewport_width,s.viewport_height,s.pixel_ratio,s.country_code,s.continent_code,s.region_code,"
                + "s.region_name,s.city,s.geo_timezone from analytics_session s "
                + "join analytics_visitor v on v.id=s.visitor_id and v.site_id=s.site_id "
                + "where s.site_id=? and (s.started_at at time zone ?)::date between ? and ? and ("
                + context.filter().expression() + "))";
    }

    private static String eventScope(String eventAlias, String sessionAlias) {
        String time = EVENT_TIME.replace("e.", eventAlias + ".");
        return eventAlias + ".site_id=" + sessionAlias + ".site_id and "
                + eventAlias + ".client_session_id=" + sessionAlias + ".client_session_id and "
                + eventAlias + ".client_visitor_id=" + sessionAlias + ".client_visitor_id and "
                + time + " between " + sessionAlias + ".started_at and " + sessionAlias + ".last_activity_at";
    }

    private static String eventBusinessDate(String eventAlias) {
        return "(" + EVENT_TIME.replace("e.", eventAlias + ".") + " at time zone ?)::date";
    }

    private int bindBase(PreparedStatement statement, QueryContext context) throws SQLException {
        int index = 1;
        statement.setObject(index++, context.siteId());
        statement.setString(index++, context.timezone());
        statement.setObject(index++, context.range().from());
        statement.setObject(index++, context.range().to());
        for (Object value : context.filter().values()) statement.setObject(index++, value);
        return index;
    }

    private <T> T single(QueryContext context, String sql, List<Object> after, Row<T> mapper) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            bindExtras(statement, bindBase(statement, context), after);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) throw new IllegalStateException("Segmented analytics query returned no row");
                return mapper.map(row);
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query segmented analytics", error);
        }
    }

    private <T> List<T> list(QueryContext context, String sql, List<Object> after, Row<T> mapper) {
        List<T> result = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            bindExtras(statement, bindBase(statement, context), after);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) result.add(mapper.map(rows));
            }
            return result;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query segmented analytics", error);
        }
    }

    private static int bindExtras(PreparedStatement statement, int index, List<Object> values) throws SQLException {
        for (Object value : values) statement.setObject(index++, value);
        return index;
    }

    private static double ratio(long value, long total) {
        return total == 0 ? 0d : (double) value / total;
    }

    private record QueryContext(
            UUID siteId, AnalyticsQueryService.Range range, String timezone, SegmentService.SessionFilter filter) {}

    public record SiteSearchReport(
            long searches,
            long uniqueVisitors,
            long sessions,
            long zeroResultSearches,
            long measuredResultSearches,
            Double averageResultsCount,
            List<SiteSearchTerm> terms) {}

    public record SiteSearchTerm(
            String keyword,
            String category,
            long searches,
            long uniqueVisitors,
            long sessions,
            long zeroResultSearches,
            long measuredResultSearches,
            Double averageResultsCount) {}

    public record ContentReport(
            long impressions,
            long interactions,
            long uniqueVisitors,
            long sessions,
            double interactionRate,
            List<ContentEntry> entries) {}

    public record ContentEntry(
            String name,
            String piece,
            String target,
            long impressions,
            long interactions,
            long uniqueVisitors,
            long sessions,
            double interactionRate) {}

    public record WebVitalsReport(List<WebVitalSummary> metrics, List<WebVitalPage> pages) {}

    public record WebVitalSummary(
            String metric,
            long samples,
            long uniqueVisitors,
            long sessions,
            double p75,
            long good,
            long needsImprovement,
            long poor) {}

    public record WebVitalPage(
            String metric,
            String pagePath,
            long samples,
            long uniqueVisitors,
            long sessions,
            double p75,
            long good,
            long needsImprovement,
            long poor) {}

    private record VisitorProfileActionCursor(AnalyticsQueryService.VisitorProfileAction action, String ingestId) {}

    private record VisitorHistoryCursor(Instant at, String rowId) {
        private static String encode(String kind, String visitorId, Instant at, String rowId) {
            String raw = String.join("|", kind, encodePart(visitorId), at.toString(), encodePart(rowId));
            return Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString(raw.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }

        private static VisitorHistoryCursor decode(String token, String expectedKind, String visitorId) {
            if (token == null) return null;
            try {
                if (token.length() > 2048) throw new IllegalArgumentException("Cursor is too long");
                String raw = new String(Base64.getUrlDecoder().decode(token), java.nio.charset.StandardCharsets.UTF_8);
                String[] parts = raw.split("\\|", -1);
                if (parts.length != 4 || !expectedKind.equals(parts[0]) || !visitorId.equals(decodePart(parts[1])))
                    throw new IllegalArgumentException("Cursor mismatch");
                Instant at = Instant.parse(parts[2]);
                String rowId = decodePart(parts[3]);
                if (rowId.isBlank() || rowId.length() > 128) throw new IllegalArgumentException("Invalid row key");
                if ("a".equals(expectedKind)) UUID.fromString(rowId);
                return new VisitorHistoryCursor(at, rowId);
            } catch (RuntimeException error) {
                throw new ControlPlaneException(
                        400, "INVALID_VISITOR_HISTORY_CURSOR", "Visitor history cursor is invalid");
            }
        }

        private static String encodePart(String value) {
            return Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString(value.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }

        private static String decodePart(String value) {
            return new String(Base64.getUrlDecoder().decode(value), java.nio.charset.StandardCharsets.UTF_8);
        }
    }

    private interface Row<T> {
        T map(ResultSet row) throws SQLException;
    }
}
