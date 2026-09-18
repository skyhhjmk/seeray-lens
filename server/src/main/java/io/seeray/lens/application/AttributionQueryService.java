package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.math.BigDecimal;
import java.sql.*;
import java.util.*;
import javax.sql.DataSource;

/** Reconstructs goal journeys from site-local visit facts and assigns fractional channel credit. */
@ApplicationScoped
public class AttributionQueryService {
    private static final String EVENT_TIME = "(case when ge.occurred_at < ge.received_at - interval '24 hours' "
            + "or ge.occurred_at > ge.received_at + interval '24 hours' then ge.received_at else ge.occurred_at end)";
    private static final Set<String> MODELS =
            Set.of("first_touch", "last_touch", "linear", "position_based", "time_decay");
    private static final Set<Integer> LOOKBACK_DAYS = Set.of(7, 30, 90);

    private final DataSource dataSource;
    private final SiteService sites;
    private final SegmentService segments;

    @Inject
    public AttributionQueryService(DataSource dataSource, SiteService sites, SegmentService segments) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.segments = segments;
    }

    public Report report(
            UUID siteId,
            AnalyticsQueryService.Range range,
            UUID segmentId,
            UUID goalId,
            String requestedModel,
            int lookbackDays) {
        String model = requestedModel == null ? "last_touch" : requestedModel;
        if (!MODELS.contains(model) || !LOOKBACK_DAYS.contains(lookbackDays)) {
            throw new ControlPlaneException(
                    400, "INVALID_ATTRIBUTION_QUERY", "Choose a supported attribution model and lookback window");
        }
        Site site = sites.site(siteId);
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        String conversionSql = conversionWeightExpression(model);
        String sql = "with eligible_sessions as ("
                + "select s.id,s.site_id,s.visitor_id,s.identity_key,v.client_visitor_id,s.client_session_id,s.started_at,s.last_activity_at,"
                + "s.initial_referrer_host,s.initial_page_host,s.initial_utm_source,s.initial_utm_medium,s.initial_utm_campaign,"
                + "s.initial_utm_term,s.initial_utm_content "
                + "from analytics_session s join analytics_visitor v on v.id=s.visitor_id and v.site_id=s.site_id "
                + "where s.site_id=? and (" + filter.expression() + ")),"
                + "conversions as (select s.site_id,s.id conversion_session_id,s.visitor_id,s.identity_key,s.client_visitor_id,"
                + "g.id goal_id,g.name goal_name,g.fixed_value,min(" + EVENT_TIME + ") conversion_at "
                + "from eligible_sessions s join raw_event ge on ge.site_id=s.site_id "
                + "and ge.client_visitor_id=s.client_visitor_id and ge.client_session_id=s.client_session_id "
                + "and " + EVENT_TIME + " between s.started_at and s.last_activity_at "
                + "join goal_definition g on g.site_id=s.site_id and g.enabled "
                + "where ((g.trigger_type='event' and ge.event_type=g.event_type and (g.event_name is null "
                + "or coalesce(nullif(ge.event_data->>'name',''),nullif(ge.event_data->'data'->>'name',''))=g.event_name)) "
                + "or (g.trigger_type='page_view' and ge.event_type='page_view' and "
                + "((g.path_match_mode='exact' and ge.page_path=g.path_pattern) or "
                + "(g.path_match_mode='contains' and position(g.path_pattern in coalesce(ge.page_path,''))>0)))) "
                + "and (" + EVENT_TIME + " at time zone ?)::date between ? and ? "
                + (goalId == null ? "" : "and g.id=? ")
                + "group by s.site_id,s.id,s.visitor_id,s.identity_key,s.client_visitor_id,g.id,g.name,g.fixed_value),"
                + "classified_sessions as (select classified.*,case when classified.channel='campaign' "
                + "then nullif(classified.initial_utm_source,'') when classified.channel='direct' then null "
                + "else nullif(classified.initial_referrer_host,'') end source from ("
                + "select s.id,s.site_id,s.identity_key,s.started_at,s.initial_referrer_host,s.initial_utm_source,"
                + "s.initial_utm_medium,s.initial_utm_campaign," + AcquisitionClassifier.channelSql("s")
                + " channel from analytics_session s where s.site_id=?) classified),"
                + "touches as (select c.goal_id,c.goal_name,c.conversion_session_id,c.conversion_at,c.fixed_value,"
                + "t.id touch_session_id,t.started_at touch_at,t.channel,t.source,t.initial_utm_medium medium,"
                + "t.initial_utm_campaign campaign,row_number() over(partition by c.goal_id,c.conversion_session_id "
                + "order by t.started_at,t.id) touch_number,count(*) over(partition by c.goal_id,c.conversion_session_id) touch_count "
                + "from conversions c join classified_sessions t on t.site_id=c.site_id and t.identity_key=c.identity_key "
                + "and t.started_at<=c.conversion_at and t.started_at>=c.conversion_at-(? * interval '1 day')),"
                + "raw_weights as (select *," + conversionSql + " raw_weight from touches),"
                + "weighted as (select goal_id,goal_name,conversion_session_id,fixed_value,channel,source,medium,campaign,"
                + "raw_weight/nullif(sum(raw_weight) over(partition by goal_id,conversion_session_id),0) credit "
                + "from raw_weights where raw_weight>0) "
                + "select goal_id,goal_name,channel,source,medium,campaign,sum(credit),sum(credit*fixed_value) "
                + "from weighted group by goal_id,goal_name,channel,source,medium,campaign "
                + "order by sum(credit) desc,goal_name,channel,source nulls last";

        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int next = 1;
            statement.setObject(next++, siteId);
            for (Object value : filter.values()) statement.setObject(next++, value);
            statement.setString(next++, site.timezone);
            statement.setObject(next++, range.from());
            statement.setObject(next++, range.to());
            if (goalId != null) statement.setObject(next++, goalId);
            statement.setObject(next++, siteId);
            statement.setInt(next, lookbackDays);
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    rows.add(new Row(
                            result.getObject(1, UUID.class),
                            result.getString(2),
                            result.getString(3),
                            result.getString(4),
                            result.getString(5),
                            result.getString(6),
                            result.getBigDecimal(7),
                            result.getBigDecimal(8)));
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query conversion attribution", error);
        }
        BigDecimal creditedConversions =
                rows.stream().map(Row::attributedConversions).reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal attributedValue = rows.stream().map(Row::attributedValue).reduce(BigDecimal.ZERO, BigDecimal::add);
        return new Report(model, lookbackDays, creditedConversions, attributedValue, List.copyOf(rows));
    }

    private static String conversionWeightExpression(String model) {
        return switch (model) {
            case "first_touch" -> "case when touch_number=1 then 1::numeric else 0::numeric end";
            case "last_touch" -> "case when touch_number=touch_count then 1::numeric else 0::numeric end";
            case "linear" -> "1::numeric/touch_count";
            case "position_based" -> "case when touch_count=1 then 1::numeric "
                    + "when touch_count=2 then 0.5::numeric when touch_number in (1,touch_count) then 0.4::numeric "
                    + "else 0.2::numeric/(touch_count-2) end";
            case "time_decay" -> "power(2::numeric,-greatest(0,extract(epoch from (conversion_at-touch_at))/604800))";
            default -> throw new IllegalArgumentException("Unsupported attribution model");
        };
    }

    public record Report(
            String model,
            int lookbackDays,
            BigDecimal attributedConversions,
            BigDecimal attributedValue,
            List<Row> rows) {}

    public record Row(
            UUID goalId,
            String goalName,
            String channel,
            String source,
            String medium,
            String campaign,
            BigDecimal attributedConversions,
            BigDecimal attributedValue) {}
}
