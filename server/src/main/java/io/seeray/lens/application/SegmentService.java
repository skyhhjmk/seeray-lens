package io.seeray.lens.application;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import javax.sql.DataSource;

/** Saved, human-readable audience rules and matching-session previews. */
@ApplicationScoped
public class SegmentService {
    private static final int MAX_SEGMENTS_PER_SITE = 30;
    private static final int MAX_RULES = 10;
    private static final String EVENT_TIME = "case when e.occurred_at < e.received_at - interval '24 hours' "
            + "or e.occurred_at > e.received_at + interval '24 hours' then e.received_at else e.occurred_at end";
    private static final Set<String> TEXT_FIELDS = Set.of(
            "entry_page",
            "exit_page",
            "source",
            "medium",
            "campaign",
            "campaign_term",
            "campaign_content",
            "referrer",
            "event_type",
            "page_path",
            "browser",
            "operating_system",
            "device_type",
            "language",
            "country",
            "region",
            "city",
            "custom_property");

    private final DataSource dataSource;
    private final ObjectMapper mapper;
    private final SiteService sites;
    private final WorkspaceAccess access;

    @Inject
    public SegmentService(DataSource dataSource, ObjectMapper mapper, SiteService sites, WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.mapper = mapper;
        this.sites = sites;
        this.access = access;
    }

    public List<View> list(UUID siteId) {
        Site site = readableSite(siteId);
        List<View> result = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select id,name,description,match_mode,rules_json,enabled,created_at,updated_at from segment_definition where site_id=? order by name,id")) {
            statement.setObject(1, site.id);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) result.add(view(rows));
            }
            return result;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list segments", error);
        }
    }

    @Transactional
    public View create(UUID siteId, Update update) {
        Site site = writableSite(siteId);
        validate(update);
        try (Connection connection = dataSource.getConnection()) {
            lockSite(connection, siteId);
            try (PreparedStatement count =
                    connection.prepareStatement("select count(*) from segment_definition where site_id=?")) {
                count.setObject(1, siteId);
                try (ResultSet row = count.executeQuery()) {
                    row.next();
                    if (row.getInt(1) >= MAX_SEGMENTS_PER_SITE)
                        throw new ControlPlaneException(
                                409, "SEGMENT_LIMIT_REACHED", "A site can have at most 30 segments");
                }
            }
            UUID id = UuidV7.next();
            Instant now = Instant.now();
            try (PreparedStatement insert = connection.prepareStatement(
                    "insert into segment_definition(id,site_id,name,description,match_mode,rules_json,enabled,created_at,updated_at) values(?,?,?,?,?,?::jsonb,?,?,?)")) {
                bind(insert, siteId, update, now);
                insert.setObject(1, id);
                insert.executeUpdate();
            }
            return get(connection, siteId, id);
        } catch (SQLException error) {
            if ("23505".equals(error.getSQLState()))
                throw new ControlPlaneException(409, "SEGMENT_NAME_EXISTS", "A segment with this name already exists");
            throw new IllegalStateException("Could not create segment", error);
        }
    }

    @Transactional
    public View update(UUID siteId, UUID segmentId, Update update) {
        writableSite(siteId);
        validate(update);
        if (!update.enabled() && experimentReferences(siteId, segmentId))
            throw new ControlPlaneException(
                    409, "SEGMENT_IN_USE", "Remove this segment from experiments before disabling it");
        String sql =
                "update segment_definition set name=?,description=?,match_mode=?,rules_json=?::jsonb,enabled=?,updated_at=? where site_id=? and id=?";
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, update.name().trim());
            statement.setString(2, normalizeDescription(update.description()));
            statement.setString(3, update.matchMode());
            statement.setString(4, rulesJson(update.rules()));
            statement.setBoolean(5, update.enabled());
            statement.setTimestamp(6, Timestamp.from(Instant.now()));
            statement.setObject(7, siteId);
            statement.setObject(8, segmentId);
            if (statement.executeUpdate() == 0) throw notFound();
            return get(connection, siteId, segmentId);
        } catch (SQLException error) {
            if ("23505".equals(error.getSQLState()))
                throw new ControlPlaneException(409, "SEGMENT_NAME_EXISTS", "A segment with this name already exists");
            throw new IllegalStateException("Could not update segment", error);
        }
    }

    @Transactional
    public void delete(UUID siteId, UUID segmentId) {
        writableSite(siteId);
        if (experimentReferences(siteId, segmentId))
            throw new ControlPlaneException(
                    409, "SEGMENT_IN_USE", "Remove this segment from experiments before deleting it");
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement =
                        connection.prepareStatement("delete from segment_definition where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, segmentId);
            if (statement.executeUpdate() == 0) throw notFound();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not delete segment", error);
        }
    }

    public Preview preview(UUID siteId, Update update, AnalyticsQueryService.Range range) {
        Site site = readableSite(siteId);
        validate(update);
        Criteria criteria = criteria(update.matchMode(), update.rules());
        String cte = matchingSessions(criteria);
        try (Connection connection = dataSource.getConnection()) {
            long sessions;
            long visitors;
            long pageViews;
            long bounced;
            long duration;
            try (PreparedStatement statement = connection.prepareStatement(cte
                    + " select count(*),count(distinct visitor_id),(select count(*) from matching_sessions m "
                    + "join raw_event e on " + eventSessionScope("e", "m")
                    + " where e.event_type='page_view' and (" + EVENT_TIME + " at time zone ?)::date between ? and ?),"
                    + "count(*) filter(where is_bounce),coalesce(sum(duration_ms),0) from matching_sessions")) {
                int next = bindRange(statement, siteId, site.timezone, range, criteria.values(), 1);
                statement.setString(next++, site.timezone);
                statement.setObject(next++, range.from());
                statement.setObject(next, range.to());
                try (ResultSet row = statement.executeQuery()) {
                    row.next();
                    sessions = row.getLong(1);
                    visitors = row.getLong(2);
                    pageViews = row.getLong(3);
                    bounced = row.getLong(4);
                    duration = row.getLong(5);
                }
            }
            List<PageCount> pages = previewPages(connection, cte, siteId, site.timezone, range, criteria);
            return new Preview(
                    sessions,
                    visitors,
                    pageViews,
                    ratio(bounced, sessions),
                    sessions == 0 ? 0 : duration / sessions,
                    pages);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not preview segment", error);
        }
    }

    public Preview preview(UUID siteId, UUID segmentId, AnalyticsQueryService.Range range) {
        View segment = get(siteId, segmentId);
        if (!segment.enabled())
            throw new ControlPlaneException(409, "SEGMENT_DISABLED", "Enable this segment before previewing it");
        return preview(
                siteId,
                new Update(segment.name(), segment.description(), segment.matchMode(), segment.rules(), true),
                range);
    }

    public SessionFilter sessionFilter(UUID siteId, UUID segmentId) {
        if (segmentId == null) return new SessionFilter("true", List.of());
        View segment = get(siteId, segmentId);
        if (!segment.enabled())
            throw new ControlPlaneException(
                    409, "SEGMENT_DISABLED", "Enable this segment before applying it to reports");
        Criteria criteria = criteria(segment.matchMode(), segment.rules());
        return new SessionFilter(criteria.expression(), List.copyOf(criteria.values()));
    }

    /**
     * Resolves an anonymous visitor against any recorded session in the selected lookback window.
     * This is used only by the origin-checked public experiment-definition endpoint; segment rules
     * and names are never returned to the browser.
     */
    public boolean matchesVisitor(UUID siteId, UUID segmentId, String clientVisitorId, int lookbackDays) {
        if (siteId == null
                || segmentId == null
                || clientVisitorId == null
                || clientVisitorId.isBlank()
                || lookbackDays < 1
                || lookbackDays > 365) return false;
        try (Connection connection = dataSource.getConnection()) {
            View segment;
            try (PreparedStatement statement = connection.prepareStatement(
                    "select id,name,description,match_mode,rules_json,enabled,created_at,updated_at from segment_definition where site_id=? and id=?")) {
                statement.setObject(1, siteId);
                statement.setObject(2, segmentId);
                try (ResultSet row = statement.executeQuery()) {
                    if (!row.next()) return false;
                    segment = view(row);
                }
            }
            if (!segment.enabled()) return false;
            Criteria criteria = criteria(segment.matchMode(), segment.rules());
            String sql = "select exists(select 1 from analytics_session s "
                    + "join analytics_visitor v on v.id=s.visitor_id and v.site_id=s.site_id "
                    + "where s.site_id=? and v.client_visitor_id=? "
                    + "and s.started_at >= now() - (? * interval '1 day') and (" + criteria.expression() + "))";
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                statement.setObject(1, siteId);
                statement.setString(2, clientVisitorId);
                statement.setInt(3, lookbackDays);
                int parameter = 4;
                for (Object value : criteria.values()) statement.setObject(parameter++, value);
                try (ResultSet row = statement.executeQuery()) {
                    row.next();
                    return row.getBoolean(1);
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not evaluate experiment audience segment", error);
        }
    }

    /** Combines a saved segment with report-local rules using the same validated rule language. */
    public SessionFilter sessionFilter(UUID siteId, UUID segmentId, String matchMode, List<Rule> rules) {
        SessionFilter saved = sessionFilter(siteId, segmentId);
        if (rules == null || rules.isEmpty()) return saved;
        Criteria local = criteria(matchMode == null ? "all" : matchMode, rules);
        if (saved.expression().equals("true")) return new SessionFilter(local.expression(), local.values());
        List<Object> values = new ArrayList<>(saved.values());
        values.addAll(local.values());
        return new SessionFilter("(" + saved.expression() + ") and (" + local.expression() + ")", List.copyOf(values));
    }

    public static void validateReportRules(String matchMode, List<Rule> rules) {
        if (rules == null || rules.isEmpty()) return;
        try {
            validateRules(matchMode == null ? "all" : matchMode, rules);
        } catch (ControlPlaneException error) {
            throw new ControlPlaneException(400, "INVALID_CUSTOM_REPORT", "One or more report filters are invalid");
        }
    }

    private List<PageCount> previewPages(
            Connection connection,
            String cte,
            UUID siteId,
            String timezone,
            AnalyticsQueryService.Range range,
            Criteria criteria)
            throws SQLException {
        String sql = cte + " select e.page_path,count(*) from raw_event e join matching_sessions s "
                + "on " + eventSessionScope("e", "s")
                + " where e.event_type='page_view' and (" + EVENT_TIME + " at time zone ?)::date between ? and ? "
                + "and e.page_path is not null group by e.page_path order by count(*) desc,e.page_path asc limit 5";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            int next = bindRange(statement, siteId, timezone, range, criteria.values(), 1);
            statement.setString(next++, timezone);
            statement.setObject(next++, range.from());
            statement.setObject(next, range.to());
            List<PageCount> pages = new ArrayList<>();
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) pages.add(new PageCount(rows.getString(1), rows.getLong(2)));
            }
            return pages;
        }
    }

    private String matchingSessions(Criteria criteria) {
        return "with matching_sessions as (select s.id,s.site_id,s.visitor_id,v.client_visitor_id,s.client_session_id,s.started_at,s.last_activity_at,s.page_view_count,s.event_count,s.duration_ms,s.is_bounce,s.visitor_type,s.entry_page,s.exit_page,s.initial_utm_source,s.initial_utm_medium,s.initial_utm_campaign,s.initial_utm_term,s.initial_utm_content,s.initial_referrer_host,s.initial_page_host from analytics_session s join analytics_visitor v on v.id=s.visitor_id and v.site_id=s.site_id where s.site_id=? and (s.started_at at time zone ?)::date between ? and ? and ("
                + criteria.expression() + "))";
    }

    private static String eventSessionScope(String eventAlias, String sessionAlias) {
        String eventTime = EVENT_TIME.replace("e.", eventAlias + ".");
        return eventAlias + ".site_id=" + sessionAlias + ".site_id and "
                + eventAlias + ".client_session_id=" + sessionAlias + ".client_session_id and "
                + eventAlias + ".client_visitor_id=(select v.client_visitor_id from analytics_visitor v where v.id="
                + sessionAlias + ".visitor_id and v.site_id=" + sessionAlias + ".site_id) and "
                + eventTime + " between " + sessionAlias + ".started_at and " + sessionAlias + ".last_activity_at";
    }

    private int bindRange(
            PreparedStatement statement,
            UUID siteId,
            String timezone,
            AnalyticsQueryService.Range range,
            List<Object> values,
            int start)
            throws SQLException {
        statement.setObject(start++, siteId);
        statement.setString(start++, timezone);
        statement.setObject(start++, range.from());
        statement.setObject(start++, range.to());
        for (Object value : values) statement.setObject(start++, value);
        return start;
    }

    private Criteria criteria(String matchMode, List<Rule> rules) {
        validateRules(matchMode, rules);
        List<String> expressions = new ArrayList<>();
        List<Object> values = new ArrayList<>();
        for (Rule rule : rules) expressions.add(ruleExpression(rule, values));
        return new Criteria(String.join(matchMode.equals("all") ? " and " : " or ", expressions), values);
    }

    private static String ruleExpression(Rule rule, List<Object> values) {
        String field = rule.field();
        String operator = rule.operator();
        String value = rule.value() == null ? "" : rule.value().trim();
        if (field.equals("event_type") || field.equals("page_path") || field.equals("custom_property")) {
            String source = field.equals("event_type")
                    ? "e.event_type"
                    : field.equals("page_path") ? "e.page_path" : "e.event_data #>> ARRAY['data',cast(? as text)]";
            if (field.equals("custom_property")) {
                // Keep SQL placeholder order explicit: the property key appears before a comparison value.
                values.add(rule.dimensionKey());
                String condition = stringCondition("property.property_value", operator, value, values);
                return "exists(select 1 from raw_event e cross join lateral (select e.event_data #>> ARRAY['data',cast(? as text)] as property_value) property "
                        + "where " + eventSessionScope("e", "s") + " and "
                        + condition + ")";
            }
            String condition = stringCondition(source, operator, value, values);
            String nonNull = field.equals("event_type") ? "e.event_type is not null" : "e.page_path is not null";
            String exists = "exists(select 1 from raw_event e where " + eventSessionScope("e", "s") + " and " + nonNull
                    + " and " + condition + ")";
            return exists;
        }
        String column =
                switch (field) {
                    case "visitor_type" -> "s.visitor_type";
                    case "entry_page" -> "s.entry_page";
                    case "exit_page" -> "s.exit_page";
                    case "source" -> "s.initial_utm_source";
                    case "medium" -> "s.initial_utm_medium";
                    case "campaign" -> "s.initial_utm_campaign";
                    case "campaign_term" -> "s.initial_utm_term";
                    case "campaign_content" -> "s.initial_utm_content";
                    case "referrer" -> "s.initial_referrer_host";
                    case "browser" -> "s.browser";
                    case "operating_system" -> "s.operating_system";
                    case "device_type" -> "s.device_type";
                    case "language" -> "s.language";
                    case "country" -> "s.country_code";
                    case "region" -> "coalesce(s.region_name,s.region_code)";
                    case "city" -> "s.city";
                    case "bounce" -> "s.is_bounce";
                    case "page_views" -> "s.page_view_count";
                    default -> throw invalid();
                };
        if (operator.equals("is_set")) return column + " is not null and " + column + " <> ''";
        if (operator.equals("is_not_set")) return "(" + column + " is null or " + column + " = '')";
        if (field.equals("bounce")) {
            values.add(Boolean.parseBoolean(value));
            return column + (operator.equals("does_not_equal") ? " <> ?" : " = ?");
        }
        if (field.equals("page_views")) {
            values.add(Integer.parseInt(value));
            return column
                    + switch (operator) {
                        case "equals" -> " = ?";
                        case "greater_than" -> " > ?";
                        case "at_least" -> " >= ?";
                        case "less_than" -> " < ?";
                        case "at_most" -> " <= ?";
                        default -> throw invalid();
                    };
        }
        return stringCondition(column, operator, value, values);
    }

    private static String stringCondition(String column, String operator, String value, List<Object> values) {
        if (operator.equals("is_set")) return column + " is not null and " + column + " <> ''";
        if (operator.equals("is_not_set")) return "(" + column + " is null or " + column + " = '')";
        String escaped = value.replace("!", "!!").replace("%", "!%").replace("_", "!_");
        return switch (operator) {
            case "equals" -> {
                values.add(value);
                yield column + " = ?";
            }
            case "does_not_equal" -> {
                values.add(value);
                yield column + " <> ?";
            }
            case "contains" -> {
                values.add("%" + escaped + "%");
                yield column + " ilike ? escape '!'";
            }
            case "starts_with" -> {
                values.add(escaped + "%");
                yield column + " ilike ? escape '!'";
            }
            default -> throw invalid();
        };
    }

    private void validate(Update update) {
        if (update == null
                || update.name() == null
                || update.name().isBlank()
                || update.name().trim().length() > 128
                || update.description() != null && update.description().length() > 512) throw invalid();
        validateRules(update.matchMode(), update.rules());
    }

    private static void validateRules(String matchMode, List<Rule> rules) {
        if (!("all".equals(matchMode) || "any".equals(matchMode))
                || rules == null
                || rules.isEmpty()
                || rules.size() > MAX_RULES) throw invalid();
        for (Rule rule : rules) {
            if (rule == null || rule.field() == null || rule.operator() == null) throw invalid();
            String field = rule.field();
            String operator = rule.operator();
            if (field.equals("visitor_type")) {
                requireOperator(operator, Set.of("equals", "does_not_equal"));
                if (!Set.of("new", "returning").contains(rule.value())) throw invalid();
            } else if (field.equals("bounce")) {
                requireOperator(operator, Set.of("equals", "does_not_equal"));
                if (!Set.of("true", "false").contains(rule.value())) throw invalid();
            } else if (field.equals("page_views")) {
                requireOperator(operator, Set.of("equals", "greater_than", "at_least", "less_than", "at_most"));
                try {
                    int count = Integer.parseInt(rule.value());
                    if (count < 0 || count > 1_000_000) throw invalid();
                } catch (Exception error) {
                    throw invalid();
                }
            } else if (TEXT_FIELDS.contains(field)) {
                Set<String> operators =
                        Set.of("equals", "does_not_equal", "contains", "starts_with", "is_set", "is_not_set");
                requireOperator(operator, operators);
                if (!isSet(operator)
                        && (rule.value() == null
                                || rule.value().isBlank()
                                || rule.value().length() > 512)) throw invalid();
                if (field.equals("custom_property")
                        && (rule.dimensionKey() == null || !rule.dimensionKey().matches("[a-z][a-z0-9_]{0,63}")))
                    throw invalid();
            } else throw invalid();
        }
    }

    private static void requireOperator(String operator, Set<String> allowed) {
        if (!allowed.contains(operator)) throw invalid();
    }

    private static boolean isSet(String operator) {
        return operator.equals("is_set") || operator.equals("is_not_set");
    }

    private Site readableSite(UUID siteId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        return site;
    }

    private Site writableSite(UUID siteId) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return site;
    }

    private static void lockSite(Connection connection, UUID siteId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement("select id from site where id=? for update")) {
            statement.setObject(1, siteId);
            statement.executeQuery().close();
        }
    }

    private void bind(PreparedStatement statement, UUID siteId, Update update, Instant now) throws SQLException {
        statement.setObject(2, siteId);
        statement.setString(3, update.name().trim());
        statement.setString(4, normalizeDescription(update.description()));
        statement.setString(5, update.matchMode());
        statement.setString(6, rulesJson(update.rules()));
        statement.setBoolean(7, update.enabled());
        statement.setTimestamp(8, Timestamp.from(now));
        statement.setTimestamp(9, Timestamp.from(now));
    }

    private String rulesJson(List<Rule> rules) {
        try {
            return mapper.writeValueAsString(rules);
        } catch (Exception error) {
            throw new IllegalArgumentException("Segment rules are invalid", error);
        }
    }

    public View get(UUID siteId, UUID segmentId) {
        readableSite(siteId);
        try (Connection connection = dataSource.getConnection()) {
            return get(connection, siteId, segmentId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read segment", error);
        }
    }

    private boolean experimentReferences(UUID siteId, UUID segmentId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select exists(select 1 from experiment_definition where site_id=? and targeting_json->>'segmentId'=?)")) {
            statement.setObject(1, siteId);
            statement.setString(2, segmentId.toString());
            try (ResultSet row = statement.executeQuery()) {
                row.next();
                return row.getBoolean(1);
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not check experiment segment references", error);
        }
    }

    private View get(Connection connection, UUID siteId, UUID segmentId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "select id,name,description,match_mode,rules_json,enabled,created_at,updated_at from segment_definition where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, segmentId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) throw notFound();
                return view(row);
            }
        }
    }

    private View view(ResultSet row) throws SQLException {
        try {
            List<Rule> rules = mapper.readValue(row.getString(5), new TypeReference<>() {});
            return new View(
                    row.getObject(1, UUID.class),
                    row.getString(2),
                    row.getString(3),
                    row.getString(4),
                    rules,
                    row.getBoolean(6),
                    row.getTimestamp(7).toInstant(),
                    row.getTimestamp(8).toInstant());
        } catch (Exception error) {
            throw new SQLException("Could not decode segment rules", error);
        }
    }

    private static String normalizeDescription(String description) {
        return description == null ? "" : description.trim();
    }

    private static double ratio(long value, long total) {
        return total == 0 ? 0d : (double) value / total;
    }

    private static ControlPlaneException notFound() {
        return new ControlPlaneException(404, "SEGMENT_NOT_FOUND", "Segment was not found");
    }

    private static ControlPlaneException invalid() {
        return new ControlPlaneException(400, "INVALID_SEGMENT", "Segment rules are invalid");
    }

    private record Criteria(String expression, List<Object> values) {}

    public record Update(String name, String description, String matchMode, List<Rule> rules, boolean enabled) {}

    public record SessionFilter(String expression, List<Object> values) {}

    public record Rule(String field, String operator, String value, String dimensionKey) {}

    public record PageCount(String path, long pageViews) {}

    public record Preview(
            long sessions,
            long visitors,
            long pageViews,
            double bounceRate,
            long averageSessionDurationMs,
            List<PageCount> topPages) {}

    public record View(
            UUID id,
            String name,
            String description,
            String matchMode,
            List<Rule> rules,
            boolean enabled,
            Instant createdAt,
            Instant updatedAt) {}
}
