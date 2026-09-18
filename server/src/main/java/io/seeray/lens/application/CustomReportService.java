package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.util.*;
import javax.sql.DataSource;

/** Bounded, parameterized ad-hoc reports over the session fact model. */
@ApplicationScoped
public class CustomReportService {
    private static final String CUSTOM_DIMENSION_PREFIX = "custom:";
    private static final String EVENT_PROPERTY_PREFIX = "event_property:";
    private static final int EVENT_PROPERTY_MAX_DEPTH = 5;
    private static final String EVENT_TIME = "(case when e.occurred_at < e.received_at - interval '24 hours' "
            + "or e.occurred_at > e.received_at + interval '24 hours' then e.received_at else e.occurred_at end)";
    private static final Map<String, String> DIMENSIONS = Map.ofEntries(
            Map.entry("entry_page", "s.entry_page"),
            Map.entry("exit_page", "s.exit_page"),
            Map.entry("entry_page_title", "s.entry_page_title"),
            Map.entry("exit_page_title", "s.exit_page_title"),
            Map.entry("referrer", "s.initial_referrer_host"),
            Map.entry("source", "s.initial_utm_source"),
            Map.entry("medium", "s.initial_utm_medium"),
            Map.entry("campaign", "s.initial_utm_campaign"),
            Map.entry("campaign_term", "s.initial_utm_term"),
            Map.entry("campaign_content", "s.initial_utm_content"),
            Map.entry("visitor_type", "s.visitor_type"),
            Map.entry("browser", "s.browser"),
            Map.entry("operating_system", "s.operating_system"),
            Map.entry("device_type", "s.device_type"),
            Map.entry("language", "s.language"),
            Map.entry("country", "s.country_code"),
            Map.entry("region", "coalesce(s.region_name,s.region_code)"),
            Map.entry("city", "s.city"));
    private static final Set<String> EVENT_DIMENSIONS = Set.of("event_type");
    private static final Map<String, String> METRICS = Map.of(
            "sessions", "count(*)::double precision",
            "unique_visitors", "count(distinct s.visitor_id)::double precision",
            "page_views", "coalesce(sum(s.page_view_count),0)::double precision",
            "events", "coalesce(sum(s.event_count),0)::double precision",
            "bounced_sessions", "count(*) filter(where s.is_bounce)::double precision",
            "average_duration_ms", "coalesce(avg(s.duration_ms),0)::double precision",
            "bounce_rate",
                    "case when count(*)=0 then 0 else count(*) filter(where s.is_bounce)::double precision/count(*) end");

    private final DataSource dataSource;
    private final AnalyticsQueryService analytics;
    private final SiteService sites;
    private final SegmentService segments;

    @Inject
    public CustomReportService(
            DataSource dataSource, AnalyticsQueryService analytics, SiteService sites, SegmentService segments) {
        this.dataSource = dataSource;
        this.analytics = analytics;
        this.sites = sites;
        this.segments = segments;
    }

    public Result query(UUID siteId, String from, String to, UUID segmentId, Query request) {
        AnalyticsQueryService.Range range = analytics.range(siteId, from, to);
        validate(request);
        Site site = sites.site(siteId);
        SegmentService.SessionFilter filter =
                segments.sessionFilter(siteId, segmentId, request.matchMode(), request.filters());
        String metric = metricExpression(request, false);
        if (request.quaternaryDimension() != null) {
            List<String> dimensions = List.of(
                    request.dimension(),
                    request.secondaryDimension(),
                    request.tertiaryDimension(),
                    request.quaternaryDimension());
            if (dimensions.stream().allMatch(DIMENSIONS::containsKey))
                return querySessionDimensionQuadruple(siteId, site, range, filter, request, metric);
            return queryEventDimensionQuadruple(siteId, site, range, filter, request, metric);
        }
        if (request.tertiaryDimension() != null) {
            List<String> dimensions =
                    List.of(request.dimension(), request.secondaryDimension(), request.tertiaryDimension());
            if (dimensions.stream().allMatch(DIMENSIONS::containsKey))
                return querySessionDimensionTriple(siteId, site, range, filter, request, metric);
            return queryEventDimensionTriple(siteId, site, range, filter, request, metric);
        }
        if (request.secondaryDimension() != null) {
            if (DIMENSIONS.containsKey(request.dimension()) && DIMENSIONS.containsKey(request.secondaryDimension()))
                return querySessionDimensionPair(siteId, site, range, filter, request, metric);
            DimensionDefinition firstCustom = eventPropertyDimension(siteId, request.dimension());
            DimensionDefinition secondCustom = eventPropertyDimension(siteId, request.secondaryDimension());
            return queryEventDimensionPair(siteId, site, range, filter, request, metric, firstCustom, secondCustom);
        }
        DimensionDefinition eventProperty = eventPropertyDimension(siteId, request.dimension());
        if (eventProperty != null) {
            DimensionDefinition definition = eventProperty;
            return queryCustomDimension(siteId, site, range, filter, request, metric, definition);
        }
        if (EVENT_DIMENSIONS.contains(request.dimension())) {
            return queryEventType(siteId, site, range, filter, request, metric);
        }
        String dimension = "coalesce(nullif(btrim(" + DIMENSIONS.get(request.dimension()) + "),''),'Unknown')";
        String sql = "with matching_sessions as (select s.id,s.site_id,s.visitor_id,s.client_session_id,s.started_at,"
                + "s.last_activity_at,s.page_view_count,s.event_count,s.duration_ms,s.is_bounce,s.visitor_type,"
                + "s.entry_page,s.exit_page,s.entry_page_title,s.exit_page_title,s.initial_referrer_host,"
                + "s.initial_page_host,s.initial_utm_source,s.initial_utm_medium,s.initial_utm_campaign,s.initial_utm_term,s.initial_utm_content,"
                + "s.browser,s.operating_system,s.device_type,s.language,s.country_code,s.region_code,s.region_name,s.city "
                + "from analytics_session s where s.site_id=? and (s.started_at at time zone ?)::date between ? and ? and ("
                + filter.expression() + ")) select " + dimension + " dimension_value," + metric + " metric_value "
                + "from matching_sessions s group by 1 order by 2 desc,1 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = 1;
            statement.setObject(index++, siteId);
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            for (Object value : filter.values()) statement.setObject(index++, value);
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) rows.add(new Row(result.getString(1), result.getDouble(2)));
            }
            return new Result(request.dimension(), null, request.metric(), null, rows, formulaName(request));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query custom report", error);
        }
    }

    /** Lists observed scalar event-property paths without returning the property values themselves. */
    public List<EventProperty> eventProperties(UUID siteId, String from, String to, UUID segmentId) {
        AnalyticsQueryService.Range range = analytics.range(siteId, from, to);
        Site site = sites.site(siteId);
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        String sql = "with recursive matching_sessions as (select s.id,s.site_id,s.client_session_id,"
                + "v.client_visitor_id,s.started_at,s.last_activity_at from analytics_session s "
                + "join analytics_visitor v on v.id=s.visitor_id and v.site_id=s.site_id "
                + "where s.site_id=? and (s.started_at at time zone ?)::date between ? and ? and ("
                + filter.expression() + ")), sampled_events as (select s.id session_id,e.event_data->'data' value "
                + "from matching_sessions s join raw_event e on " + eventScope("e", "s") + " where "
                + eventBusinessDate("e")
                + " between ? and ? order by e.occurred_at desc,e.ingest_id desc limit 10000), "
                + "property_tree(session_id,value,path,depth) as (select session_id,value,ARRAY[]::text[],0 "
                + "from sampled_events union all select t.session_id,child.value,t.path||child.key,t.depth+1 "
                + "from property_tree t cross join lateral ("
                + "select key,value from jsonb_each(case when jsonb_typeof(t.value)='object' then t.value else '{}'::jsonb end) "
                + "union all select ordinal::text,value from jsonb_array_elements(case when jsonb_typeof(t.value)='array' "
                + "then t.value else '[]'::jsonb end) with ordinality as item(value,ordinal)) child "
                + "where t.depth<? and jsonb_typeof(t.value) in ('object','array')) "
                + "select path,count(*) event_count,count(distinct session_id) session_count from property_tree "
                + "where depth>0 and jsonb_typeof(value) in ('string','number','boolean') "
                + "group by path order by count(*) desc,path asc limit 250";
        List<EventProperty> properties = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = 1;
            statement.setObject(index++, siteId);
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            for (Object value : filter.values()) statement.setObject(index++, value);
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            statement.setInt(index, EVENT_PROPERTY_MAX_DEPTH);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    Array pathArray = rows.getArray(1);
                    try {
                        String[] path = (String[]) pathArray.getArray();
                        if (!safePropertyPath(path)) continue;
                        properties.add(new EventProperty(
                                eventPropertyDimensionId(path),
                                eventPropertyLabel(path),
                                rows.getLong(2),
                                rows.getLong(3)));
                    } finally {
                        pathArray.free();
                    }
                }
            }
            return List.copyOf(properties);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list custom report event properties", error);
        }
    }

    private Result querySessionDimensionTriple(
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter,
            Query request,
            String metric) {
        List<String> expressions =
                List.of(request.dimension(), request.secondaryDimension(), request.tertiaryDimension()).stream()
                        .map(name -> "coalesce(nullif(btrim(" + DIMENSIONS.get(name) + "),''),'Unknown')")
                        .toList();
        String sql = "with matching_sessions as (select s.id,s.site_id,s.visitor_id,s.client_session_id,s.started_at,"
                + "s.last_activity_at,s.page_view_count,s.event_count,s.duration_ms,s.is_bounce,s.visitor_type,"
                + "s.entry_page,s.exit_page,s.entry_page_title,s.exit_page_title,s.initial_referrer_host,"
                + "s.initial_page_host,s.initial_utm_source,s.initial_utm_medium,s.initial_utm_campaign,s.initial_utm_term,s.initial_utm_content,"
                + "s.browser,s.operating_system,s.device_type,s.language,s.country_code,s.region_code,s.region_name,s.city "
                + "from analytics_session s where s.site_id=? and (s.started_at at time zone ?)::date between ? and ? and ("
                + filter.expression() + ")) select " + expressions.get(0) + " dimension_value,"
                + expressions.get(1) + " secondary_dimension_value," + expressions.get(2)
                + " tertiary_dimension_value," + metric + " metric_value from matching_sessions s group by 1,2,3 "
                + "order by 4 desc,1 asc,2 asc,3 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = bindSessionBase(statement, siteId, site, range, filter);
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next())
                    rows.add(new Row(
                            result.getString(1), result.getDouble(4), result.getString(2), result.getString(3)));
            }
            return new Result(
                    request.dimension(),
                    request.secondaryDimension(),
                    request.metric(),
                    null,
                    rows,
                    formulaName(request),
                    null,
                    request.tertiaryDimension(),
                    null);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query three session dimensions", error);
        }
    }

    private Result queryEventDimensionTriple(
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter,
            Query request,
            String metric) {
        List<String> names = List.of(request.dimension(), request.secondaryDimension(), request.tertiaryDimension());
        List<DimensionDefinition> customDimensions =
                names.stream().map(name -> eventPropertyDimension(siteId, name)).toList();
        List<String> expressions = new ArrayList<>(3);
        StringBuilder propertyJoins = new StringBuilder();
        for (int index = 0; index < names.size(); index++) {
            DimensionDefinition custom = customDimensions.get(index);
            expressions.add(pairDimensionExpression(names.get(index), custom, index));
            if (custom != null) propertyJoins.append(pairPropertyJoin(index));
        }
        boolean containsEventType = names.stream().anyMatch(EVENT_DIMENSIONS::contains);
        String sql = customDimensionSessionsCte(filter)
                + ", event_dimension_triples as (select s.id session_id,s.visitor_id,s.page_view_count,s.duration_ms,"
                + "s.is_bounce," + expressions.get(0) + " dimension_value," + expressions.get(1)
                + " secondary_dimension_value," + expressions.get(2)
                + " tertiary_dimension_value,count(*)::integer event_count from matching_sessions s "
                + "join raw_event e on " + eventScope("e", "s") + propertyJoins + " where "
                + eventBusinessDate("e") + " between ? and ?"
                + (containsEventType ? " and e.event_type<>'web_vital'" : "")
                + " group by s.id,s.visitor_id,s.page_view_count,s.duration_ms,s.is_bounce,"
                + String.join(",", expressions)
                + ") select s.dimension_value,s.secondary_dimension_value,s.tertiary_dimension_value," + metric
                + " metric_value from event_dimension_triples s group by s.dimension_value,s.secondary_dimension_value,"
                + "s.tertiary_dimension_value order by 4 desc,1 asc,2 asc,3 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = bindSessionBase(statement, siteId, site, range, filter);
            for (DimensionDefinition custom : customDimensions) {
                if (custom != null) {
                    index = bindPropertyPath(connection, statement, index, custom);
                }
            }
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next())
                    rows.add(new Row(
                            result.getString(1), result.getDouble(4), result.getString(2), result.getString(3)));
            }
            return new Result(
                    request.dimension(),
                    request.secondaryDimension(),
                    request.metric(),
                    customDimensions.get(0) == null
                            ? null
                            : customDimensions.get(0).name(),
                    rows,
                    formulaName(request),
                    customDimensions.get(1) == null
                            ? null
                            : customDimensions.get(1).name(),
                    request.tertiaryDimension(),
                    customDimensions.get(2) == null
                            ? null
                            : customDimensions.get(2).name());
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query three event dimensions", error);
        }
    }

    private Result querySessionDimensionQuadruple(
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter,
            Query request,
            String metric) {
        List<String> names = List.of(
                request.dimension(),
                request.secondaryDimension(),
                request.tertiaryDimension(),
                request.quaternaryDimension());
        List<String> expressions = names.stream()
                .map(name -> "coalesce(nullif(btrim(" + DIMENSIONS.get(name) + "),''),'Unknown')")
                .toList();
        String projection = String.join(",", expressions);
        String sql = "with matching_sessions as (select s.id,s.site_id,s.visitor_id,s.client_session_id,s.started_at,"
                + "s.last_activity_at,s.page_view_count,s.event_count,s.duration_ms,s.is_bounce,s.visitor_type,"
                + "s.entry_page,s.exit_page,s.entry_page_title,s.exit_page_title,s.initial_referrer_host,"
                + "s.initial_page_host,s.initial_utm_source,s.initial_utm_medium,s.initial_utm_campaign,s.initial_utm_term,s.initial_utm_content,"
                + "s.browser,s.operating_system,s.device_type,s.language,s.country_code,s.region_code,s.region_name,s.city "
                + "from analytics_session s where s.site_id=? and (s.started_at at time zone ?)::date between ? and ? and ("
                + filter.expression() + ")) select " + projection
                + "," + metric + " metric_value from matching_sessions s group by 1,2,3,4 "
                + "order by 5 desc,1 asc,2 asc,3 asc,4 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = bindSessionBase(statement, siteId, site, range, filter);
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next())
                    rows.add(new Row(
                            result.getString(1),
                            result.getDouble(5),
                            result.getString(2),
                            result.getString(3),
                            result.getString(4)));
            }
            return new Result(
                    request.dimension(),
                    request.secondaryDimension(),
                    request.metric(),
                    null,
                    rows,
                    formulaName(request),
                    null,
                    request.tertiaryDimension(),
                    null,
                    request.quaternaryDimension(),
                    null);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query four session dimensions", error);
        }
    }

    private Result queryEventDimensionQuadruple(
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter,
            Query request,
            String metric) {
        List<String> names = List.of(
                request.dimension(),
                request.secondaryDimension(),
                request.tertiaryDimension(),
                request.quaternaryDimension());
        List<DimensionDefinition> customDimensions =
                names.stream().map(name -> eventPropertyDimension(siteId, name)).toList();
        List<String> expressions = new ArrayList<>(names.size());
        StringBuilder propertyJoins = new StringBuilder();
        for (int index = 0; index < names.size(); index++) {
            DimensionDefinition custom = customDimensions.get(index);
            expressions.add(pairDimensionExpression(names.get(index), custom, index));
            if (custom != null) propertyJoins.append(pairPropertyJoin(index));
        }
        boolean containsEventType = names.stream().anyMatch(EVENT_DIMENSIONS::contains);
        List<String> aliases = List.of(
                "dimension_value",
                "secondary_dimension_value",
                "tertiary_dimension_value",
                "quaternary_dimension_value");
        String eventProjection = java.util.stream.IntStream.range(0, expressions.size())
                .mapToObj(index -> expressions.get(index) + " " + aliases.get(index))
                .collect(java.util.stream.Collectors.joining(","));
        String groupExpressions = String.join(",", expressions);
        String outerProjection = "s.dimension_value,s.secondary_dimension_value,s.tertiary_dimension_value,"
                + "s.quaternary_dimension_value";
        String sql = customDimensionSessionsCte(filter)
                + ", event_dimension_quadruples as (select s.id session_id,s.visitor_id,s.page_view_count,s.duration_ms,"
                + "s.is_bounce," + eventProjection + ",count(*)::integer event_count from matching_sessions s "
                + "join raw_event e on " + eventScope("e", "s") + propertyJoins + " where "
                + eventBusinessDate("e") + " between ? and ?"
                + (containsEventType ? " and e.event_type<>'web_vital'" : "")
                + " group by s.id,s.visitor_id,s.page_view_count,s.duration_ms,s.is_bounce," + groupExpressions
                + ") select " + outerProjection + "," + metric
                + " metric_value from event_dimension_quadruples s group by 1,2,3,4 "
                + "order by 5 desc,1 asc,2 asc,3 asc,4 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = bindSessionBase(statement, siteId, site, range, filter);
            for (DimensionDefinition custom : customDimensions) {
                if (custom != null) {
                    index = bindPropertyPath(connection, statement, index, custom);
                }
            }
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next())
                    rows.add(new Row(
                            result.getString(1),
                            result.getDouble(5),
                            result.getString(2),
                            result.getString(3),
                            result.getString(4)));
            }
            return new Result(
                    request.dimension(),
                    request.secondaryDimension(),
                    request.metric(),
                    customDimensions.get(0) == null
                            ? null
                            : customDimensions.get(0).name(),
                    rows,
                    formulaName(request),
                    customDimensions.get(1) == null
                            ? null
                            : customDimensions.get(1).name(),
                    request.tertiaryDimension(),
                    customDimensions.get(2) == null
                            ? null
                            : customDimensions.get(2).name(),
                    request.quaternaryDimension(),
                    customDimensions.get(3) == null
                            ? null
                            : customDimensions.get(3).name());
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query four event dimensions", error);
        }
    }

    private Result querySessionDimensionPair(
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter,
            Query request,
            String metric) {
        String dimension = "coalesce(nullif(btrim(" + DIMENSIONS.get(request.dimension()) + "),''),'Unknown')";
        String secondaryDimension =
                "coalesce(nullif(btrim(" + DIMENSIONS.get(request.secondaryDimension()) + "),''),'Unknown')";
        String sql = "with matching_sessions as (select s.id,s.site_id,s.visitor_id,s.client_session_id,s.started_at,"
                + "s.last_activity_at,s.page_view_count,s.event_count,s.duration_ms,s.is_bounce,s.visitor_type,"
                + "s.entry_page,s.exit_page,s.entry_page_title,s.exit_page_title,s.initial_referrer_host,"
                + "s.initial_page_host,s.initial_utm_source,s.initial_utm_medium,s.initial_utm_campaign,s.initial_utm_term,s.initial_utm_content,"
                + "s.browser,s.operating_system,s.device_type,s.language,s.country_code,s.region_code,s.region_name,s.city "
                + "from analytics_session s where s.site_id=? and (s.started_at at time zone ?)::date between ? and ? and ("
                + filter.expression() + ")) select " + dimension + " dimension_value," + secondaryDimension
                + " secondary_dimension_value," + metric + " metric_value from matching_sessions s group by 1,2 "
                + "order by 3 desc,1 asc,2 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = 1;
            statement.setObject(index++, siteId);
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            for (Object value : filter.values()) statement.setObject(index++, value);
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) rows.add(new Row(result.getString(1), result.getDouble(3), result.getString(2)));
            }
            return new Result(
                    request.dimension(),
                    request.secondaryDimension(),
                    request.metric(),
                    null,
                    rows,
                    formulaName(request));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query paired custom report dimensions", error);
        }
    }

    private Result queryEventDimensionPair(
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter,
            Query request,
            String metric,
            DimensionDefinition firstCustom,
            DimensionDefinition secondCustom) {
        String first = pairDimensionExpression(request.dimension(), firstCustom, 0);
        String second = pairDimensionExpression(request.secondaryDimension(), secondCustom, 1);
        StringBuilder propertyJoins = new StringBuilder();
        if (firstCustom != null) propertyJoins.append(pairPropertyJoin(0));
        if (secondCustom != null) propertyJoins.append(pairPropertyJoin(1));
        boolean containsEventType = EVENT_DIMENSIONS.contains(request.dimension())
                || EVENT_DIMENSIONS.contains(request.secondaryDimension());
        String sql = customDimensionSessionsCte(filter)
                + ", event_dimension_pairs as (select s.id session_id,s.visitor_id,s.page_view_count,s.duration_ms,"
                + "s.is_bounce," + first + " dimension_value," + second + " secondary_dimension_value,"
                + "count(*)::integer event_count from matching_sessions s join raw_event e on "
                + eventScope("e", "s") + propertyJoins + " where " + eventBusinessDate("e") + " between ? and ?"
                + (containsEventType ? " and e.event_type<>'web_vital'" : "")
                + " group by s.id,s.visitor_id,s.page_view_count,s.duration_ms,s.is_bounce," + first + "," + second
                + ") "
                + "select s.dimension_value,s.secondary_dimension_value," + metric
                + " metric_value from event_dimension_pairs s group by s.dimension_value,s.secondary_dimension_value "
                + "order by 3 desc,1 asc,2 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = bindSessionBase(statement, siteId, site, range, filter);
            if (firstCustom != null) {
                index = bindPropertyPath(connection, statement, index, firstCustom);
            }
            if (secondCustom != null) {
                index = bindPropertyPath(connection, statement, index, secondCustom);
            }
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    rows.add(new Row(result.getString(1), result.getDouble(3), result.getString(2)));
                }
            }
            String firstCustomName = firstCustom == null ? null : firstCustom.name();
            String secondCustomName = secondCustom == null ? null : secondCustom.name();
            return new Result(
                    request.dimension(),
                    request.secondaryDimension(),
                    request.metric(),
                    firstCustomName,
                    rows,
                    formulaName(request),
                    secondCustomName);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query joined event and session dimensions", error);
        }
    }

    private static String pairDimensionExpression(
            String dimension, DimensionDefinition customDimension, int customPropertyIndex) {
        if (DIMENSIONS.containsKey(dimension))
            return "coalesce(nullif(btrim(" + DIMENSIONS.get(dimension) + "),''),'Unknown')";
        if (EVENT_DIMENSIONS.contains(dimension)) return "e.event_type";
        if (customDimension != null) {
            String property = "property" + customPropertyIndex;
            return "coalesce(case when jsonb_typeof(" + property
                    + ".raw_value) in ('string','number','boolean') then nullif(btrim(" + property
                    + ".text_value),'') end,'Unknown')";
        }
        throw invalid("Choose supported dimensions for the cross-breakdown");
    }

    private static String pairPropertyJoin(int index) {
        return " cross join lateral (select e.event_data #>> cast(? as text[]) text_value,"
                + "e.event_data #> cast(? as text[]) raw_value) property"
                + index;
    }

    private Result queryEventType(
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter,
            Query request,
            String metric) {
        String sql = customDimensionSessionsCte(filter)
                + ", event_type_sessions as (select e.event_type,s.id session_id,s.visitor_id,s.page_view_count,"
                + "s.duration_ms,s.is_bounce,count(*)::integer event_count "
                + "from matching_sessions s join raw_event e on " + eventScope("e", "s")
                + " where e.event_type<>'web_vital' and " + eventBusinessDate("e") + " between ? and ? "
                + "group by e.event_type,s.id,s.visitor_id,s.page_view_count,s.duration_ms,s.is_bounce) "
                + "select s.event_type dimension_value," + metric + " metric_value from event_type_sessions s "
                + "group by s.event_type order by 2 desc,1 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = bindSessionBase(statement, siteId, site, range, filter);
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) rows.add(new Row(result.getString(1), result.getDouble(2)));
            }
            return new Result(request.dimension(), null, request.metric(), null, rows, formulaName(request));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query event type custom report", error);
        }
    }

    private Result queryCustomDimension(
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter,
            Query request,
            String metric,
            DimensionDefinition dimension) {
        if ("events".equals(request.metric())) {
            return queryDimensionEvents(siteId, site, range, filter, request, dimension);
        }
        String dimensionMetric = metricExpression(request, true);
        String sql = customDimensionSessionsCte(filter)
                + ", session_dimension_values as (select s.id session_id,"
                + "coalesce(d.dimension_value,'Unknown') dimension_value,coalesce(d.event_count,0)::integer event_count "
                + "from matching_sessions s left join lateral (select "
                + "nullif(btrim(property.text_value),'') dimension_value,count(*)::integer event_count "
                + "from raw_event e cross join lateral (select e.event_data #>> cast(? as text[]) text_value,"
                + "e.event_data #> cast(? as text[]) raw_value) property where " + eventScope("e", "s")
                + " and " + eventBusinessDate("e") + " between ? and ? "
                + "and jsonb_typeof(property.raw_value) in ('string','number','boolean') "
                + "and nullif(btrim(property.text_value),'') is not null group by 1) d on true) "
                + "select d.dimension_value dimension_value," + dimensionMetric + " metric_value "
                + "from matching_sessions s "
                + "join session_dimension_values d on d.session_id=s.id group by d.dimension_value "
                + "order by 2 desc,1 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = bindSessionBase(statement, siteId, site, range, filter);
            index = bindPropertyPath(connection, statement, index, dimension);
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) rows.add(new Row(result.getString(1), result.getDouble(2)));
            }
            return new Result(
                    request.dimension(), null, request.metric(), dimension.name(), rows, formulaName(request));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query custom dimension report", error);
        }
    }

    private Result queryDimensionEvents(
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter,
            Query request,
            DimensionDefinition dimension) {
        String sql = customDimensionSessionsCte(filter)
                + ", dimension_events as (select nullif(btrim(property.text_value),'') dimension_value "
                + "from matching_sessions s join raw_event e on " + eventScope("e", "s")
                + " cross join lateral (select e.event_data #>> cast(? as text[]) text_value,"
                + "e.event_data #> cast(? as text[]) raw_value) property "
                + "where " + eventBusinessDate("e") + " between ? and ? "
                + "and jsonb_typeof(property.raw_value) in ('string','number','boolean') "
                + "and nullif(btrim(property.text_value),'') is not null) "
                + "select dimension_value,count(*)::double precision metric_value from dimension_events "
                + "group by dimension_value order by 2 desc,1 asc limit ?";
        List<Row> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = bindSessionBase(statement, siteId, site, range, filter);
            index = bindPropertyPath(connection, statement, index, dimension);
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            statement.setInt(index, request.limit() == null ? 10 : request.limit());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) rows.add(new Row(result.getString(1), result.getDouble(2)));
            }
            return new Result(
                    request.dimension(), null, request.metric(), dimension.name(), rows, formulaName(request));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query custom dimension event report", error);
        }
    }

    private static String customDimensionSessionsCte(SegmentService.SessionFilter filter) {
        return "with matching_sessions as (select s.id,s.site_id,s.visitor_id,v.client_visitor_id,"
                + "s.client_session_id,s.started_at,s.last_activity_at,s.page_view_count,s.event_count,s.duration_ms,"
                + "s.is_bounce,s.visitor_type,s.entry_page,s.exit_page,s.entry_page_title,s.exit_page_title,"
                + "s.initial_referrer_host,s.initial_page_host,s.initial_utm_source,s.initial_utm_medium,"
                + "s.initial_utm_campaign,s.initial_utm_term,s.initial_utm_content,s.browser,s.operating_system,s.device_type,s.language,s.country_code,"
                + "s.region_code,s.region_name,s.city from analytics_session s join analytics_visitor v "
                + "on v.id=s.visitor_id and v.site_id=s.site_id where s.site_id=? "
                + "and (s.started_at at time zone ?)::date between ? and ? and (" + filter.expression() + "))";
    }

    private static int bindSessionBase(
            PreparedStatement statement,
            UUID siteId,
            Site site,
            AnalyticsQueryService.Range range,
            SegmentService.SessionFilter filter)
            throws SQLException {
        int index = 1;
        statement.setObject(index++, siteId);
        statement.setString(index++, site.timezone);
        statement.setObject(index++, range.from());
        statement.setObject(index++, range.to());
        for (Object value : filter.values()) statement.setObject(index++, value);
        return index;
    }

    private DimensionDefinition enabledDimension(UUID siteId, UUID dimensionId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement =
                        connection.prepareStatement("select dimension_key,name from custom_dimension_definition "
                                + "where site_id=? and id=? and enabled")) {
            statement.setObject(1, siteId);
            statement.setObject(2, dimensionId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) throw invalid("Choose an enabled custom dimension for this site");
                return new DimensionDefinition(List.of("data", row.getString(1)), row.getString(2));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not resolve custom report dimension", error);
        }
    }

    private static String eventScope(String eventAlias, String sessionAlias) {
        String eventTime = EVENT_TIME.replace("e.", eventAlias + ".");
        return eventAlias + ".site_id=" + sessionAlias + ".site_id and "
                + eventAlias + ".client_session_id=" + sessionAlias + ".client_session_id and "
                + eventAlias + ".client_visitor_id=" + sessionAlias + ".client_visitor_id and "
                + eventTime + " between " + sessionAlias + ".started_at and " + sessionAlias + ".last_activity_at";
    }

    private static String eventBusinessDate(String eventAlias) {
        return "(" + EVENT_TIME.replace("e.", eventAlias + ".") + " at time zone ?)::date";
    }

    private static UUID customDimensionId(String dimension) {
        if (dimension == null || !dimension.startsWith(CUSTOM_DIMENSION_PREFIX)) return null;
        String value = dimension.substring(CUSTOM_DIMENSION_PREFIX.length());
        if (!validUuid(value)) throw invalid("Choose a valid custom dimension");
        return UUID.fromString(value);
    }

    private DimensionDefinition eventPropertyDimension(UUID siteId, String dimension) {
        UUID customId = customDimensionId(dimension);
        if (customId != null) return enabledDimension(siteId, customId);
        if (dimension == null || !dimension.startsWith(EVENT_PROPERTY_PREFIX)) return null;
        String encoded = dimension.substring(EVENT_PROPERTY_PREFIX.length());
        if (encoded.isEmpty() || encoded.length() > 1024 || !encoded.matches("[A-Za-z0-9_-]+"))
            throw invalid("Choose a valid event-property path");
        try {
            String decoded =
                    new String(Base64.getUrlDecoder().decode(encoded), java.nio.charset.StandardCharsets.UTF_8);
            String[] path = decoded.split("\u001f", -1);
            if (!safePropertyPath(path)) throw invalid("Choose a valid event-property path");
            List<String> fullPath = new ArrayList<>(path.length + 1);
            fullPath.add("data");
            fullPath.addAll(List.of(path));
            return new DimensionDefinition(fullPath, eventPropertyLabel(path));
        } catch (IllegalArgumentException error) {
            throw invalid("Choose a valid event-property path");
        }
    }

    private static String eventPropertyDimensionId(String[] path) {
        String joined = String.join("\u001f", path);
        String encoded = Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(joined.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        return EVENT_PROPERTY_PREFIX + encoded;
    }

    private static String eventPropertyLabel(String[] path) {
        return String.join(
                " › ",
                Arrays.stream(path)
                        .map(part -> part.matches("[0-9]+") ? "[" + part + "]" : part)
                        .toList());
    }

    private static boolean safePropertyPath(String[] path) {
        if (path == null || path.length == 0 || path.length > EVENT_PROPERTY_MAX_DEPTH) return false;
        for (String part : path) {
            if (part == null
                    || part.isBlank()
                    || part.length() > 80
                    || part.chars().anyMatch(Character::isISOControl)) return false;
            String normalized = part.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]", "");
            if (List.of(
                            "password",
                            "passwd",
                            "secret",
                            "token",
                            "authorization",
                            "auth",
                            "credential",
                            "bearer",
                            "apikey",
                            "privatekey",
                            "accesskey",
                            "refreshkey",
                            "email",
                            "phone",
                            "mobile",
                            "address",
                            "ipaddress",
                            "ssn",
                            "creditcard",
                            "cardnumber")
                    .stream()
                    .anyMatch(normalized::contains)) return false;
        }
        return true;
    }

    private static int bindPropertyPath(
            Connection connection, PreparedStatement statement, int index, DimensionDefinition dimension)
            throws SQLException {
        Array path = connection.createArrayOf("text", dimension.path().toArray(String[]::new));
        statement.setArray(index++, path);
        statement.setArray(index++, path);
        return index;
    }

    private static boolean validUuid(String value) {
        return value != null
                && value.matches("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
    }

    private static void validate(Query query) {
        if (query == null) throw invalid("Choose a supported dimension and metric");
        String dimension = query.dimension();
        if (!supportedDimension(dimension)
                || query.metric() == null
                || !("formula".equals(query.metric()) || METRICS.containsKey(query.metric())))
            throw invalid("Choose a supported dimension and metric");
        if ("formula".equals(query.metric())) validateFormula(query.formula());
        else if (query.formula() != null) throw invalid("A calculated metric is only valid for formula reports");
        String secondaryDimension = query.secondaryDimension();
        if (secondaryDimension != null
                && (!supportedDimension(secondaryDimension) || dimension.equalsIgnoreCase(secondaryDimension)))
            throw invalid("Choose two different supported dimensions for a cross-breakdown");
        String tertiaryDimension = query.tertiaryDimension();
        if (tertiaryDimension != null
                && (!supportedDimension(tertiaryDimension)
                        || dimension.equalsIgnoreCase(tertiaryDimension)
                        || secondaryDimension == null
                        || secondaryDimension.equalsIgnoreCase(tertiaryDimension)))
            throw invalid("Choose up to four different supported dimensions for a cross-breakdown");
        String quaternaryDimension = query.quaternaryDimension();
        if (quaternaryDimension != null
                && (!supportedDimension(quaternaryDimension)
                        || tertiaryDimension == null
                        || dimension.equalsIgnoreCase(quaternaryDimension)
                        || secondaryDimension.equalsIgnoreCase(quaternaryDimension)
                        || tertiaryDimension.equalsIgnoreCase(quaternaryDimension)))
            throw invalid("Choose up to four different supported dimensions for a cross-breakdown");
        if (query.limit() != null && query.limit() != 5 && query.limit() != 10 && query.limit() != 20)
            throw invalid("Choose 5, 10, or 20 report rows");
        if (query.filters() != null && query.filters().size() > 5)
            throw invalid("A custom report can contain at most 5 filters");
        if (query.filters() != null
                && !query.filters().isEmpty()
                && !Set.of("all", "any").contains(query.matchMode()))
            throw invalid("Choose whether all or any report filters must match");
    }

    static boolean supportedDimension(String dimension) {
        return dimension != null
                && (DIMENSIONS.containsKey(dimension)
                        || EVENT_DIMENSIONS.contains(dimension)
                        || dimension.startsWith(CUSTOM_DIMENSION_PREFIX)
                                && validUuid(dimension.substring(CUSTOM_DIMENSION_PREFIX.length()))
                        || validEventPropertyDimension(dimension));
    }

    private static boolean validEventPropertyDimension(String dimension) {
        if (dimension == null || !dimension.startsWith(EVENT_PROPERTY_PREFIX)) return false;
        String encoded = dimension.substring(EVENT_PROPERTY_PREFIX.length());
        if (encoded.isEmpty() || encoded.length() > 1024 || !encoded.matches("[A-Za-z0-9_-]+")) return false;
        try {
            return safePropertyPath(
                    new String(Base64.getUrlDecoder().decode(encoded), java.nio.charset.StandardCharsets.UTF_8)
                            .split("\u001f", -1));
        } catch (IllegalArgumentException error) {
            return false;
        }
    }

    static void validateFormula(Formula formula) {
        if (formula == null) throw invalid("Configure the calculated metric");
        String name = formula.name() == null ? "" : formula.name().strip();
        if (name.isBlank() || name.length() > 80 || name.chars().anyMatch(Character::isISOControl))
            throw invalid("Calculated metric names must contain 1 to 80 visible characters");
        if (formula.leftMetric() == null
                || formula.rightMetric() == null
                || !METRICS.containsKey(formula.leftMetric())
                || !METRICS.containsKey(formula.rightMetric()))
            throw invalid("Choose supported measures for the calculated metric");
        if (formula.operator() == null
                || !Set.of("add", "subtract", "multiply", "divide").contains(formula.operator()))
            throw invalid("Choose a supported calculated metric operation");
        if (formula.format() == null || !Set.of("number", "percent").contains(formula.format()))
            throw invalid("Choose a number or percentage output format");
    }

    private static String metricExpression(Query request, boolean customDimension) {
        if (!"formula".equals(request.metric())) return METRICS.get(request.metric());
        Formula formula = request.formula();
        String left = formulaMetric(formula.leftMetric(), customDimension);
        String right = formulaMetric(formula.rightMetric(), customDimension);
        String operation =
                switch (formula.operator()) {
                    case "add" -> "+";
                    case "subtract" -> "-";
                    case "multiply" -> "*";
                    case "divide" -> "/";
                    default -> throw invalid("Choose a supported calculated metric operation");
                };
        String value = "divide".equals(formula.operator())
                ? "case when (" + right + ")=0 then 0 else (" + left + ")/ (" + right + ") end"
                : "(" + left + ") " + operation + " (" + right + ")";
        if ("percent".equals(formula.format())) value = "(" + value + ") * 100";
        return "(" + value + ")::double precision";
    }

    private static String formulaMetric(String metric, boolean customDimension) {
        if (customDimension && "events".equals(metric)) return "coalesce(sum(d.event_count),0)::double precision";
        return METRICS.get(metric);
    }

    private static String formulaName(Query request) {
        return request.formula() == null ? null : request.formula().name().strip();
    }

    private static ControlPlaneException invalid(String message) {
        return new ControlPlaneException(400, "INVALID_CUSTOM_REPORT", message);
    }

    public record Query(
            String dimension,
            String secondaryDimension,
            String tertiaryDimension,
            String quaternaryDimension,
            String metric,
            Integer limit,
            String matchMode,
            List<SegmentService.Rule> filters,
            Formula formula) {
        public Query(
                String dimension,
                String secondaryDimension,
                String tertiaryDimension,
                String metric,
                Integer limit,
                String matchMode,
                List<SegmentService.Rule> filters,
                Formula formula) {
            this(dimension, secondaryDimension, tertiaryDimension, null, metric, limit, matchMode, filters, formula);
        }

        public Query(
                String dimension,
                String secondaryDimension,
                String metric,
                Integer limit,
                String matchMode,
                List<SegmentService.Rule> filters,
                Formula formula) {
            this(dimension, secondaryDimension, null, null, metric, limit, matchMode, filters, formula);
        }
    }

    public record Formula(String name, String leftMetric, String operator, String rightMetric, String format) {}

    public record Row(
            String dimensionValue,
            double metricValue,
            String secondaryDimensionValue,
            String tertiaryDimensionValue,
            String quaternaryDimensionValue) {
        public Row(
                String dimensionValue,
                double metricValue,
                String secondaryDimensionValue,
                String tertiaryDimensionValue) {
            this(dimensionValue, metricValue, secondaryDimensionValue, tertiaryDimensionValue, null);
        }

        public Row(String dimensionValue, double metricValue) {
            this(dimensionValue, metricValue, null, null, null);
        }

        public Row(String dimensionValue, double metricValue, String secondaryDimensionValue) {
            this(dimensionValue, metricValue, secondaryDimensionValue, null, null);
        }
    }

    public record Result(
            String dimension,
            String secondaryDimension,
            String metric,
            String customDimensionName,
            List<Row> rows,
            String formulaName,
            String secondaryCustomDimensionName,
            String tertiaryDimension,
            String tertiaryCustomDimensionName,
            String quaternaryDimension,
            String quaternaryCustomDimensionName) {
        public Result(
                String dimension,
                String secondaryDimension,
                String metric,
                String customDimensionName,
                List<Row> rows,
                String formulaName,
                String secondaryCustomDimensionName,
                String tertiaryDimension,
                String tertiaryCustomDimensionName) {
            this(
                    dimension,
                    secondaryDimension,
                    metric,
                    customDimensionName,
                    rows,
                    formulaName,
                    secondaryCustomDimensionName,
                    tertiaryDimension,
                    tertiaryCustomDimensionName,
                    null,
                    null);
        }

        public Result(
                String dimension,
                String secondaryDimension,
                String metric,
                String customDimensionName,
                List<Row> rows,
                String formulaName,
                String secondaryCustomDimensionName) {
            this(
                    dimension,
                    secondaryDimension,
                    metric,
                    customDimensionName,
                    rows,
                    formulaName,
                    secondaryCustomDimensionName,
                    null,
                    null,
                    null,
                    null);
        }

        public Result(
                String dimension,
                String secondaryDimension,
                String metric,
                String customDimensionName,
                List<Row> rows,
                String formulaName) {
            this(
                    dimension,
                    secondaryDimension,
                    metric,
                    customDimensionName,
                    rows,
                    formulaName,
                    null,
                    null,
                    null,
                    null,
                    null);
        }

        public Result(
                String dimension,
                String secondaryDimension,
                String metric,
                String customDimensionName,
                List<Row> rows) {
            this(dimension, secondaryDimension, metric, customDimensionName, rows, null, null, null, null, null, null);
        }
    }

    private record DimensionDefinition(List<String> path, String name) {}

    public record EventProperty(String id, String label, long eventCount, long sessionCount) {}
}
