package io.seeray.lens.application;

import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.LocalDate;
import java.util.*;
import javax.sql.DataSource;

/** Reports on explicitly marked HTML audio/video elements without returning media URLs or labels. */
@ApplicationScoped
public class MediaAnalyticsService {
    private final DataSource dataSource;
    private final SiteService sites;
    private final SegmentService segments;

    @Inject
    public MediaAnalyticsService(DataSource dataSource, SiteService sites, SegmentService segments) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.segments = segments;
    }

    public Report report(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        Site site = sites.site(siteId);
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        String sql =
                """
                with media_events as (
                  select coalesce(nullif(e.event_data->'data'->>'mediaId',''), nullif(e.event_data->>'name','')) media_id,
                    coalesce(nullif(e.event_data->'data'->>'mediaType',''),'video') media_type,
                    coalesce(e.page_path,'/') page_path,coalesce(s.identity_key,'browser:'||e.client_visitor_id) identity_key,
                    e.client_session_id session_id,
                    e.event_type,
                    case when e.event_data->'data'->>'progressPercent' in ('25','50','75','90')
                      then (e.event_data->'data'->>'progressPercent')::integer end progress_percent,
                    case when e.event_data->'data'->>'mediaDurationSeconds' ~ '^[0-9]{1,6}$'
                      then (e.event_data->'data'->>'mediaDurationSeconds')::integer end duration_seconds
                  from raw_event e left join analytics_visitor v on v.site_id=e.site_id
                    and v.client_visitor_id=e.client_visitor_id
                  left join analytics_session s on s.site_id=e.site_id and s.visitor_id=v.id
                    and s.client_session_id=e.client_session_id
                    and (case when e.occurred_at < e.received_at - interval '24 hours'
                      or e.occurred_at > e.received_at + interval '24 hours'
                      then e.received_at else e.occurred_at end) between s.started_at and s.last_activity_at
                  where e.site_id=? and e.event_type in ('media_start','media_progress','media_complete')
                    and e.client_visitor_id is not null and e.client_session_id is not null
                    and (e.occurred_at at time zone ?)::date between ? and ?
                    and coalesce(nullif(e.event_data->'data'->>'mediaId',''), nullif(e.event_data->>'name',''))
                      ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
                    and coalesce(nullif(e.event_data->'data'->>'mediaType',''),'video') in ('audio','video')
                    and (%s)
                ), session_media as (
                  select media_id,media_type,page_path,identity_key,session_id,
                    bool_or(event_type='media_start') started,
                    bool_or(event_type='media_complete') completed,
                    bool_or(event_type='media_progress' and progress_percent=25) reached_25,
                    bool_or(event_type='media_progress' and progress_percent=50) reached_50,
                    bool_or(event_type='media_progress' and progress_percent=75) reached_75,
                    bool_or(event_type='media_progress' and progress_percent=90) reached_90
                  from media_events group by media_id,media_type,page_path,identity_key,session_id
                ), media_lengths as (
                  select media_id,media_type,page_path,avg(duration_seconds)::integer average_duration_seconds
                  from media_events where event_type='media_complete' and duration_seconds is not null
                  group by media_id,media_type,page_path
                ), rollups as (
                  select media_id,media_type,page_path,
                    count(*) filter(where started)::bigint starts,
                    count(*) filter(where started and reached_25)::bigint reached_25,
                    count(*) filter(where started and reached_50)::bigint reached_50,
                    count(*) filter(where started and reached_75)::bigint reached_75,
                    count(*) filter(where started and reached_90)::bigint reached_90,
                    count(*) filter(where started and completed)::bigint completions,
                    count(*) filter(where started and not completed)::bigint incomplete_sessions,
                    count(distinct identity_key) filter(where started)::bigint unique_visitors
                  from session_media group by media_id,media_type,page_path
                )
                select r.media_id,r.media_type,r.page_path,r.starts,r.reached_25,r.reached_50,r.reached_75,
                  r.reached_90,r.completions,r.incomplete_sessions,r.unique_visitors,
                  coalesce(l.average_duration_seconds,0),count(*) over() total_rows
                from rollups r left join media_lengths l on l.media_id=r.media_id and l.media_type=r.media_type
                  and l.page_path=r.page_path
                order by r.starts desc,r.completions desc,r.media_id,r.page_path limit 100
                """
                        .formatted(filter.expression());
        List<Row> rows = new ArrayList<>();
        int total = 0;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, siteId);
            statement.setString(2, site.timezone);
            statement.setObject(3, range.from());
            statement.setObject(4, range.to());
            for (int index = 0; index < filter.values().size(); index++)
                statement.setObject(5 + index, filter.values().get(index));
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    total = result.getInt(13);
                    long starts = result.getLong(4), completions = result.getLong(9);
                    rows.add(new Row(
                            result.getString(1),
                            result.getString(2),
                            result.getString(3),
                            starts,
                            result.getLong(5),
                            result.getLong(6),
                            result.getLong(7),
                            result.getLong(8),
                            completions,
                            result.getLong(10),
                            result.getLong(11),
                            result.getInt(12),
                            starts == 0 ? 0 : (double) completions / starts));
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query media analytics", error);
        }
        return new Report(range.from(), range.to(), List.copyOf(rows), total > rows.size());
    }

    public record Report(LocalDate from, LocalDate to, List<Row> rows, boolean hasMore) {}

    public record Row(
            String mediaId,
            String mediaType,
            String pagePath,
            long starts,
            long reached25,
            long reached50,
            long reached75,
            long reached90,
            long completions,
            long incompleteSessions,
            long uniqueVisitors,
            int averageDurationSeconds,
            double completionRate) {}
}
