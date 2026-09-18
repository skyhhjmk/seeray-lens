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
    private static final String GOAL_EVENT_MATCH = "((g.trigger_type='event' and e.event_type=g.event_type "
            + "and (g.event_name is null or coalesce(nullif(e.event_data->>'name',''),"
            + "nullif(e.event_data->'data'->>'name',''))=g.event_name)) "
            + "or (g.trigger_type='page_view' and e.event_type='page_view' and "
            + "((g.path_match_mode='exact' and e.page_path=g.path_pattern) or "
            + "(g.path_match_mode='contains' and position(g.path_pattern in coalesce(e.page_path,''))>0))))";

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
        return report(siteId, range, segmentId, weeks, "first_visit", null);
    }

    public List<RetentionCell> report(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId, int weeks, String basis, UUID goalId) {
        return report(siteId, range, segmentId, "week", weeks, basis, goalId);
    }

    public List<RetentionCell> report(
            UUID siteId,
            AnalyticsQueryService.Range range,
            UUID segmentId,
            String period,
            int periods,
            String basis,
            UUID goalId) {
        if (!validPeriodWindow(period, periods)) {
            throw new ControlPlaneException(400, "INVALID_COHORT_WINDOW", "Cohort period or window is invalid");
        }
        if (!"first_visit".equals(basis) && !"goal_conversion".equals(basis)) {
            throw new ControlPlaneException(400, "INVALID_COHORT_BASIS", "Cohort basis is invalid");
        }
        if ("goal_conversion".equals(basis) && goalId == null) {
            throw new ControlPlaneException(400, "GOAL_REQUIRED", "A goal is required for goal-conversion cohorts");
        }
        Site site = sites.site(siteId);
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        String cohortBucket = periodBucket("s.cohort_at", period);
        String activityBucket = periodBucket("s.started_at", period);
        String retentionIndex =
                switch (period) {
                    case "day" -> "(a.activity_period-c.cohort_period)::int";
                    case "week" -> "((a.activity_period-c.cohort_period)/7)::int";
                    case "month" -> "((extract(year from a.activity_period)-extract(year from c.cohort_period))*12+"
                            + "extract(month from a.activity_period)-extract(month from c.cohort_period))::int";
                    default -> throw new IllegalStateException("Validated cohort period was not supported");
                };
        String completionDate =
                switch (period) {
                    case "day" -> "s.cohort_period+a.period_index<=?::date";
                    case "week" -> "s.cohort_period+((a.period_index+1)*7-1)<=?::date";
                    case "month" -> "(s.cohort_period+(a.period_index+1)*interval '1 month'-interval '1 day')::date<=?::date";
                    default -> throw new IllegalStateException("Validated cohort period was not supported");
                };
        String cohortCandidates;
        if ("goal_conversion".equals(basis)) {
            cohortCandidates = "cohort_candidates as (select distinct s.*,v.client_visitor_id,"
                    + "min(case when e.occurred_at < e.received_at - interval '24 hours' "
                    + "or e.occurred_at > e.received_at + interval '24 hours' then e.received_at "
                    + "else e.occurred_at end) over(partition by s.id) cohort_at "
                    + "from analytics_session s join analytics_visitor v on v.id=s.visitor_id and v.site_id=s.site_id "
                    + "join goal_definition g on g.site_id=s.site_id and g.id=? and g.enabled "
                    + "join raw_event e on e.site_id=s.site_id and e.client_session_id=s.client_session_id "
                    + "and e.client_visitor_id=v.client_visitor_id and "
                    + "(case when e.occurred_at < e.received_at - interval '24 hours' "
                    + "or e.occurred_at > e.received_at + interval '24 hours' then e.received_at "
                    + "else e.occurred_at end) between s.started_at and s.last_activity_at "
                    + "where s.site_id=? and " + GOAL_EVENT_MATCH + "),";
        } else {
            cohortCandidates = "cohort_candidates as (select e.*,e.started_at cohort_at from eligible_sessions e),";
        }
        String sql = "with eligible_sessions as (select s.*,v.client_visitor_id from analytics_session s "
                + "join analytics_visitor v on v.id=s.visitor_id and v.site_id=s.site_id "
                + "where s.site_id=? and " + MEANINGFUL_ACTIVITY + "),"
                + cohortCandidates
                + " ranked_sessions as (select e.*,row_number() over(partition by visitor_id order by cohort_at,id) first_rank "
                + "from cohort_candidates e),"
                + " cohort_members as (select s.visitor_id," + cohortBucket + " cohort_period "
                + "from ranked_sessions s where s.first_rank=1 and "
                + "(s.cohort_at at time zone ?)::date between ? and ? and (" + filter.expression() + ")),"
                + " cohort_sizes as (select cohort_period,count(distinct visitor_id)::bigint cohort_size "
                + "from cohort_members group by cohort_period),"
                + " activity_periods as (select distinct s.visitor_id," + activityBucket + " activity_period "
                + "from eligible_sessions s where (s.started_at at time zone ?)::date<=?),"
                + " retained as (select c.cohort_period," + retentionIndex + " period_index,"
                + "count(distinct c.visitor_id)::bigint retained_visitors from cohort_members c "
                + "join activity_periods a on a.visitor_id=c.visitor_id and a.activity_period>=c.cohort_period "
                + "group by c.cohort_period,period_index),"
                + " ages as (select generate_series(0,?-1)::int period_index),"
                + " cells as (select s.cohort_period,a.period_index,s.cohort_size,"
                + "case when a.period_index=0 then s.cohort_size else coalesce(r.retained_visitors,0) end retained_visitors,"
                + "(a.period_index=0 or " + completionDate + ") complete "
                + "from cohort_sizes s cross join ages a left join retained r "
                + "on r.cohort_period=s.cohort_period and r.period_index=a.period_index) "
                + "select cohort_period,period_index,cohort_size,retained_visitors,"
                + "case when cohort_size=0 then 0 else retained_visitors::double precision/cohort_size end,complete "
                + "from cells order by cohort_period desc,period_index";

        List<RetentionCell> result = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int next = 1;
            statement.setObject(next++, siteId);
            if ("goal_conversion".equals(basis)) {
                statement.setObject(next++, goalId);
                statement.setObject(next++, siteId);
            }
            statement.setString(next++, site.timezone);
            statement.setString(next++, site.timezone);
            statement.setObject(next++, range.from());
            statement.setObject(next++, range.to());
            for (Object value : filter.values()) statement.setObject(next++, value);
            statement.setString(next++, site.timezone);
            statement.setString(next++, site.timezone);
            statement.setObject(next++, range.to());
            statement.setInt(next++, periods);
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

    private static boolean validPeriodWindow(String period, int periods) {
        if (period == null) return false;
        return switch (period) {
            case "day" -> periods == 7 || periods == 14 || periods == 30;
            case "week" -> periods == 4 || periods == 8 || periods == 12;
            case "month" -> periods == 3 || periods == 6 || periods == 12;
            default -> false;
        };
    }

    private static String periodBucket(String value, String period) {
        return switch (period) {
            case "day" -> "(" + value + " at time zone ?)::date";
            case "week" -> "date_trunc('week',(" + value + " at time zone ?)::date)::date";
            case "month" -> "date_trunc('month',(" + value + " at time zone ?)::date)::date";
            default -> throw new IllegalStateException("Validated cohort period was not supported");
        };
    }

    public record RetentionCell(
            LocalDate cohortPeriod,
            int periodIndex,
            long cohortSize,
            long retainedVisitors,
            double retentionRate,
            boolean complete) {}
}
