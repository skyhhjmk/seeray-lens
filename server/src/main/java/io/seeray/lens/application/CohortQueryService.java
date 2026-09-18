package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.LocalDate;
import java.util.*;
import javax.sql.DataSource;

/** Builds weekly acquisition cohorts and repeat-activity retention from session facts. */
@ApplicationScoped
public class CohortQueryService {
    private static final String MEANINGFUL_ACTIVITY = "(s.page_view_count>0 or exists(select 1 from raw_event e "
            + "where e.site_id=s.site_id and e.client_session_id=s.client_session_id "
            + "and e.client_visitor_id=v.client_visitor_id and "
            + "(case when e.occurred_at < e.received_at - interval '24 hours' "
            + "or e.occurred_at > e.received_at + interval '24 hours' "
            + "then e.received_at else e.occurred_at end) between s.started_at and s.last_activity_at "
            + "and e.event_type<>'heartbeat'))";

    private final DataSource dataSource;
    private final SiteService sites;
    private final SegmentService segments;

    @Inject
    public CohortQueryService(DataSource dataSource, SiteService sites, SegmentService segments) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.segments = segments;
    }

    public List<RetentionCell> report(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId, int weeks) {
        if (weeks != 4 && weeks != 8 && weeks != 12) {
            throw new ControlPlaneException(400, "INVALID_COHORT_WINDOW", "Cohort window must be 4, 8, or 12 weeks");
        }
        Site site = sites.site(siteId);
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        String sql = "with eligible_sessions as (select s.*,v.client_visitor_id from analytics_session s "
                + "join analytics_visitor v on v.id=s.visitor_id and v.site_id=s.site_id "
                + "where s.site_id=? and " + MEANINGFUL_ACTIVITY + "),"
                + " ranked_sessions as (select e.*,row_number() over(partition by visitor_id order by started_at,id) first_rank "
                + "from eligible_sessions e),"
                + " cohort_members as (select s.visitor_id,date_trunc('week',(s.started_at at time zone ?)::date)::date cohort_week "
                + "from ranked_sessions s where s.first_rank=1 and "
                + "(s.started_at at time zone ?)::date between ? and ? and (" + filter.expression() + ")),"
                + " cohort_sizes as (select cohort_week,count(distinct visitor_id)::bigint cohort_size "
                + "from cohort_members group by cohort_week),"
                + " activity_weeks as (select distinct s.visitor_id,date_trunc('week',(s.started_at at time zone ?)::date)::date activity_week "
                + "from eligible_sessions s where (s.started_at at time zone ?)::date<=?),"
                + " retained as (select c.cohort_week,((a.activity_week-c.cohort_week)/7)::int week_index,"
                + "count(distinct c.visitor_id)::bigint retained_visitors from cohort_members c "
                + "join activity_weeks a on a.visitor_id=c.visitor_id and a.activity_week>=c.cohort_week "
                + "group by c.cohort_week,week_index),"
                + " ages as (select generate_series(0,?-1)::int week_index),"
                + " cells as (select s.cohort_week,a.week_index,s.cohort_size,coalesce(r.retained_visitors,0) retained_visitors,"
                + "(a.week_index=0 or s.cohort_week+((a.week_index+1)*7-1)<=?::date) complete "
                + "from cohort_sizes s cross join ages a left join retained r "
                + "on r.cohort_week=s.cohort_week and r.week_index=a.week_index) "
                + "select cohort_week,week_index,cohort_size,retained_visitors,"
                + "case when cohort_size=0 then 0 else retained_visitors::double precision/cohort_size end,complete "
                + "from cells order by cohort_week desc,week_index";

        List<RetentionCell> result = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int next = 1;
            statement.setObject(next++, siteId);
            statement.setString(next++, site.timezone);
            statement.setString(next++, site.timezone);
            statement.setObject(next++, range.from());
            statement.setObject(next++, range.to());
            for (Object value : filter.values()) statement.setObject(next++, value);
            statement.setString(next++, site.timezone);
            statement.setString(next++, site.timezone);
            statement.setObject(next++, range.to());
            statement.setInt(next++, weeks);
            statement.setObject(next, range.to());
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    result.add(new RetentionCell(
                            rows.getObject(1, LocalDate.class),
                            rows.getInt(2),
                            rows.getLong(3),
                            rows.getLong(4),
                            rows.getDouble(5),
                            rows.getBoolean(6)));
                }
            }
            return result;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query cohort retention", error);
        }
    }

    public record RetentionCell(
            LocalDate cohortWeek,
            int weekIndex,
            long cohortSize,
            long retainedVisitors,
            double retentionRate,
            boolean complete) {}
}
