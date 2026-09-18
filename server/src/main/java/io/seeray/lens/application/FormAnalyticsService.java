package io.seeray.lens.application;

import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.LocalDate;
import java.util.*;
import javax.sql.DataSource;

/** Privacy-safe rollups for explicitly instrumented forms. Raw field data is never selected. */
@ApplicationScoped
public class FormAnalyticsService {
    private final DataSource dataSource;
    private final SiteService sites;
    private final SegmentService segments;

    @Inject
    public FormAnalyticsService(DataSource dataSource, SiteService sites, SegmentService segments) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.segments = segments;
    }

    public Report report(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        Site site = sites.site(siteId);
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        String sql =
                """
                with form_events as (
                  select coalesce(nullif(e.event_data->'data'->>'formId',''), nullif(e.event_data->>'name','')) form_id,
                    coalesce(e.page_path,'/') page_path,coalesce(s.identity_key,'browser:'||e.client_visitor_id) identity_key,
                    e.client_session_id session_id,
                    e.event_type,e.duration_ms
                  from raw_event e left join analytics_visitor v on v.site_id=e.site_id
                    and v.client_visitor_id=e.client_visitor_id
                  left join analytics_session s on s.site_id=e.site_id and s.visitor_id=v.id
                    and s.client_session_id=e.client_session_id
                    and (case when e.occurred_at < e.received_at - interval '24 hours'
                      or e.occurred_at > e.received_at + interval '24 hours'
                      then e.received_at else e.occurred_at end) between s.started_at and s.last_activity_at
                  where e.site_id=? and e.event_type in ('form_view','form_start','form_field','form_field_time',
                    'form_error','form_submit','form_success','form_failure')
                    and e.client_visitor_id is not null and e.client_session_id is not null
                    and (e.occurred_at at time zone ?)::date between ? and ?
                    and coalesce(nullif(e.event_data->'data'->>'formId',''), nullif(e.event_data->>'name',''))
                      ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
                    and (%s)
                ), session_forms as (
                  select form_id,page_path,identity_key,session_id,
                    bool_or(event_type='form_view') viewed,bool_or(event_type='form_start') started,
                    bool_or(event_type='form_submit') submitted,bool_or(event_type='form_success') successful,
                    bool_or(event_type='form_failure') failed,
                    count(*) filter(where event_type='form_field')::bigint field_interactions,
                    count(*) filter(where event_type='form_error')::bigint validation_errors
                  from form_events group by form_id,page_path,identity_key,session_id
                ), field_times as (
                  select form_id,page_path,avg(duration_ms)::bigint avg_field_time_ms
                  from form_events where event_type='form_field_time' and duration_ms is not null
                  group by form_id,page_path
                ), rollups as (
                  select form_id,page_path,count(*) filter(where viewed)::bigint views,
                    count(*) filter(where started)::bigint starts,
                    sum(field_interactions)::bigint field_interactions,
                    sum(validation_errors)::bigint validation_errors,
                    count(*) filter(where submitted)::bigint submits,
                    count(*) filter(where successful)::bigint successes,
                    count(*) filter(where failed)::bigint failures,
                    count(*) filter(where started and not submitted and not successful and not failed)::bigint abandonments,
                    count(distinct identity_key)::bigint unique_visitors
                  from session_forms group by form_id,page_path
                )
                select r.form_id,r.page_path,r.views,r.starts,r.field_interactions,r.validation_errors,r.submits,
                  r.successes,r.failures,r.abandonments,r.unique_visitors,coalesce(t.avg_field_time_ms,0),count(*) over() total_rows
                from rollups r left join field_times t on t.form_id=r.form_id and t.page_path=r.page_path
                order by r.starts desc,r.views desc,r.form_id,r.page_path limit 100
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
                    long starts = result.getLong(4), successes = result.getLong(8);
                    rows.add(new Row(
                            result.getString(1),
                            result.getString(2),
                            result.getLong(3),
                            starts,
                            result.getLong(5),
                            result.getLong(6),
                            result.getLong(7),
                            successes,
                            result.getLong(9),
                            result.getLong(10),
                            result.getLong(11),
                            result.getLong(12),
                            starts == 0 ? 0 : (double) successes / starts));
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query form analytics", error);
        }
        return new Report(range.from(), range.to(), List.copyOf(rows), total > rows.size());
    }

    public record Report(LocalDate from, LocalDate to, List<Row> rows, boolean hasMore) {}

    public record Row(
            String formId,
            String pagePath,
            long views,
            long starts,
            long fieldInteractions,
            long validationErrors,
            long submits,
            long successes,
            long failures,
            long abandonments,
            long uniqueVisitors,
            long averageFieldTimeMs,
            double conversionRate) {}
}
