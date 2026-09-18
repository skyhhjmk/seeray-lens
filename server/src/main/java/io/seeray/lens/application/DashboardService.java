package io.seeray.lens.application;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import javax.sql.DataSource;

/** Persists each user's visual dashboard layouts per site. */
@ApplicationScoped
public class DashboardService {
    private static final int MAX_DASHBOARDS = 20;
    private static final int MAX_WIDGETS = 20;
    private static final Set<String> TYPES = Set.of(
            "summary",
            "trend",
            "top_pages",
            "traffic_channels",
            "visitor_types",
            "events",
            "goals",
            "technology",
            "locations",
            "page_behaviour",
            "custom_report",
            "live_visitors");
    private static final Set<String> TREND_METRICS = Set.of("sessions", "pageViews", "uniqueVisitors");
    private static final Set<String> TECHNOLOGY_DIMENSIONS = Set.of(
            "Browser",
            "Browser version",
            "Operating system",
            "OS version",
            "Device type",
            "Language",
            "Screen size",
            "Viewport size",
            "Display scale");
    private static final Set<String> LOCATION_LEVELS = Set.of("country", "continent", "region", "city");
    private static final Set<String> REPORT_DIMENSIONS = Set.of(
            "entry_page",
            "exit_page",
            "entry_page_title",
            "exit_page_title",
            "referrer",
            "event_type",
            "source",
            "medium",
            "campaign",
            "campaign_term",
            "campaign_content",
            "visitor_type",
            "browser",
            "operating_system",
            "device_type",
            "language",
            "country",
            "region",
            "city");
    private static final Set<String> REPORT_METRICS = Set.of(
            "sessions",
            "unique_visitors",
            "page_views",
            "events",
            "bounced_sessions",
            "average_duration_ms",
            "bounce_rate",
            "formula");

    private final DataSource dataSource;
    private final ObjectMapper mapper;
    private final SiteService sites;
    private final WorkspaceAccess access;

    @Inject
    public DashboardService(DataSource dataSource, ObjectMapper mapper, SiteService sites, WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.mapper = mapper;
        this.sites = sites;
        this.access = access;
    }

    public List<View> list(UUID siteId) {
        Site site = readableSite(siteId);
        UUID userId = access.userId();
        List<View> result = new ArrayList<>();
        String sql = "select id,name,widgets::text,is_default,created_at,updated_at "
                + "from analytics_dashboard_definition where site_id=? and user_id=? "
                + "order by is_default desc,updated_at desc,id";
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, site.id);
            statement.setObject(2, userId);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) result.add(view(rows));
            }
            return result;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list dashboards", error);
        }
    }

    @Transactional
    public View create(UUID siteId, Draft draft) {
        Site site = readableSite(siteId);
        String name = validateName(draft.name());
        List<Widget> widgets = validateWidgets(draft.widgets());
        UUID userId = access.userId();
        try (Connection connection = dataSource.getConnection()) {
            lockSite(connection, siteId);
            int count = count(connection, siteId, userId);
            if (count >= MAX_DASHBOARDS)
                throw new ControlPlaneException(
                        409, "DASHBOARD_LIMIT_REACHED", "A user can save up to 20 dashboards per site");
            boolean makeDefault = draft.isDefault() || count == 0;
            if (makeDefault) clearDefault(connection, siteId, userId);
            UUID id = UuidV7.next();
            Instant now = Instant.now();
            try (PreparedStatement insert = connection.prepareStatement(
                    "insert into analytics_dashboard_definition(id,site_id,user_id,name,widgets,is_default,created_at,updated_at) "
                            + "values(?,?,?, ?,?::jsonb,?,?,?)")) {
                insert.setObject(1, id);
                insert.setObject(2, siteId);
                insert.setObject(3, userId);
                insert.setString(4, name);
                insert.setString(5, serialize(widgets));
                insert.setBoolean(6, makeDefault);
                insert.setTimestamp(7, Timestamp.from(now));
                insert.setTimestamp(8, Timestamp.from(now));
                insert.executeUpdate();
            }
            return get(connection, siteId, userId, id);
        } catch (SQLException error) {
            throw databaseError("Could not create dashboard", error);
        }
    }

    @Transactional
    public View update(UUID siteId, UUID dashboardId, Draft draft) {
        readableSite(siteId);
        String name = validateName(draft.name());
        List<Widget> widgets = validateWidgets(draft.widgets());
        UUID userId = access.userId();
        try (Connection connection = dataSource.getConnection()) {
            lockSite(connection, siteId);
            View existing = get(connection, siteId, userId, dashboardId);
            int dashboardCount = count(connection, siteId, userId);
            boolean makeDefault = draft.isDefault() || (existing.isDefault() && dashboardCount == 1);
            if (makeDefault) clearDefault(connection, siteId, userId);
            String sql = "update analytics_dashboard_definition set name=?,widgets=?::jsonb,is_default=?,updated_at=? "
                    + "where id=? and site_id=? and user_id=?";
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                statement.setString(1, name);
                statement.setString(2, serialize(widgets));
                statement.setBoolean(3, makeDefault);
                statement.setTimestamp(4, Timestamp.from(Instant.now()));
                statement.setObject(5, dashboardId);
                statement.setObject(6, siteId);
                statement.setObject(7, userId);
                if (statement.executeUpdate() == 0) throw notFound();
            }
            if (existing.isDefault() && !makeDefault) promoteOldest(connection, siteId, userId, dashboardId);
            return get(connection, siteId, userId, dashboardId);
        } catch (SQLException error) {
            throw databaseError("Could not update dashboard", error);
        }
    }

    @Transactional
    public View duplicate(UUID siteId, UUID dashboardId) {
        Site site = readableSite(siteId);
        UUID userId = access.userId();
        try (Connection connection = dataSource.getConnection()) {
            lockSite(connection, siteId);
            if (count(connection, siteId, userId) >= MAX_DASHBOARDS)
                throw new ControlPlaneException(
                        409, "DASHBOARD_LIMIT_REACHED", "A user can save up to 20 dashboards per site");
            View source = get(connection, siteId, userId, dashboardId);
            String base =
                    source.name().length() > 74 ? source.name().substring(0, 74).stripTrailing() : source.name();
            String copyName = base + " copy";
            int suffix = 2;
            while (nameExists(connection, siteId, userId, copyName)) {
                String tail = " copy " + suffix++;
                copyName = (base.length() + tail.length() > 80 ? base.substring(0, 80 - tail.length()) : base) + tail;
            }
            UUID copyId = UuidV7.next();
            Instant now = Instant.now();
            try (PreparedStatement insert = connection.prepareStatement(
                    "insert into analytics_dashboard_definition(id,site_id,user_id,name,widgets,is_default,created_at,updated_at) "
                            + "values(?,?,?, ?,?::jsonb,false,?,?)")) {
                insert.setObject(1, copyId);
                insert.setObject(2, siteId);
                insert.setObject(3, userId);
                insert.setString(4, copyName);
                insert.setString(5, serialize(source.widgets()));
                insert.setTimestamp(6, Timestamp.from(now));
                insert.setTimestamp(7, Timestamp.from(now));
                insert.executeUpdate();
            }
            return get(connection, siteId, userId, copyId);
        } catch (SQLException error) {
            throw databaseError("Could not duplicate dashboard", error);
        }
    }

    @Transactional
    public void delete(UUID siteId, UUID dashboardId) {
        readableSite(siteId);
        UUID userId = access.userId();
        try (Connection connection = dataSource.getConnection()) {
            lockSite(connection, siteId);
            View target = get(connection, siteId, userId, dashboardId);
            try (PreparedStatement statement = connection.prepareStatement(
                    "delete from analytics_dashboard_definition where id=? and site_id=? and user_id=?")) {
                statement.setObject(1, dashboardId);
                statement.setObject(2, siteId);
                statement.setObject(3, userId);
                if (statement.executeUpdate() == 0) throw notFound();
            }
            if (target.isDefault()) promoteOldest(connection, siteId, userId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not delete dashboard", error);
        }
    }

    private Site readableSite(UUID siteId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        return site;
    }

    private View get(Connection connection, UUID siteId, UUID userId, UUID dashboardId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "select id,name,widgets::text,is_default,created_at,updated_at from analytics_dashboard_definition "
                        + "where site_id=? and user_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, userId);
            statement.setObject(3, dashboardId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) throw notFound();
                return view(row);
            }
        }
    }

    private View view(ResultSet row) throws SQLException {
        try {
            List<Widget> widgets = mapper.readValue(row.getString(3), new TypeReference<>() {});
            return new View(
                    row.getObject(1, UUID.class),
                    row.getString(2),
                    widgets,
                    row.getBoolean(4),
                    row.getTimestamp(5).toInstant(),
                    row.getTimestamp(6).toInstant());
        } catch (Exception error) {
            throw new IllegalStateException("Saved dashboard layout is invalid", error);
        }
    }

    private static List<Widget> validateWidgets(List<Widget> widgets) {
        if (widgets == null || widgets.size() > MAX_WIDGETS)
            throw invalid("A dashboard can contain at most 20 widgets");
        Set<String> ids = new HashSet<>();
        List<Widget> normalized = new ArrayList<>(widgets.size());
        for (Widget widget : widgets) {
            if (widget == null
                    || widget.id() == null
                    || !widget.id().matches("[A-Za-z0-9_-]{1,64}")
                    || !ids.add(widget.id())) throw invalid("Widget identifiers must be unique");
            if (!TYPES.contains(widget.type())) throw invalid("Choose a supported dashboard widget");
            String title = widget.title() == null ? "" : widget.title().strip();
            if (title.isBlank() || title.length() > 80 || title.chars().anyMatch(Character::isISOControl))
                throw invalid("Widget titles must contain 1 to 80 visible characters");
            String metric = widget.metric();
            CustomReportService.Formula formula = widget.formula();
            Integer limit = widget.limit();
            String chartType = widget.chartType();
            String dimension = widget.dimension();
            String secondaryDimension = widget.secondaryDimension();
            String locationLevel = widget.locationLevel();
            String matchMode = widget.matchMode();
            List<SegmentService.Rule> filters = widget.filters();
            switch (widget.type()) {
                case "trend" -> {
                    if (metric == null || !TREND_METRICS.contains(metric)) throw invalid("Choose a trend metric");
                    if (chartType == null || !Set.of("line", "bar").contains(chartType))
                        throw invalid("Choose a line or bar trend chart");
                    requireNull(limit, dimension, secondaryDimension, locationLevel, matchMode, filters, formula);
                }
                case "top_pages", "traffic_channels", "events", "goals", "live_visitors" -> {
                    if (limit == null || !Set.of(5, 10, 20).contains(limit)) throw invalid("Choose 5, 10, or 20 rows");
                    requireNull(
                            metric,
                            chartType,
                            dimension,
                            secondaryDimension,
                            locationLevel,
                            matchMode,
                            filters,
                            formula);
                }
                case "technology" -> {
                    if (dimension == null || !TECHNOLOGY_DIMENSIONS.contains(dimension))
                        throw invalid("Choose a supported technology dimension");
                    if (limit == null || !Set.of(5, 10, 20).contains(limit)) throw invalid("Choose 5, 10, or 20 rows");
                    requireNull(metric, chartType, secondaryDimension, locationLevel, matchMode, filters, formula);
                }
                case "locations" -> {
                    if (locationLevel == null || !LOCATION_LEVELS.contains(locationLevel))
                        throw invalid("Choose a location level");
                    if (limit == null || !Set.of(5, 10, 20).contains(limit)) throw invalid("Choose 5, 10, or 20 rows");
                    requireNull(metric, chartType, dimension, secondaryDimension, matchMode, filters, formula);
                }
                case "custom_report" -> {
                    if (!supportedReportDimension(dimension))
                        throw invalid("Choose a supported custom report dimension");
                    if (metric == null || !REPORT_METRICS.contains(metric))
                        throw invalid("Choose a supported custom report metric");
                    if ("formula".equals(metric)) CustomReportService.validateFormula(formula);
                    else if (formula != null) throw invalid("A calculated metric is only valid for formula reports");
                    if (limit == null || !Set.of(5, 10, 20).contains(limit))
                        throw invalid("Choose 5, 10, or 20 report rows");
                    if (chartType == null || !Set.of("table", "bars").contains(chartType))
                        throw invalid("Choose a table or bar display");
                    if (secondaryDimension != null
                            && (!supportedReportDimension(secondaryDimension)
                                    || dimension.equalsIgnoreCase(secondaryDimension)))
                        throw invalid("Choose two different supported dimensions for a cross-breakdown");
                    if (locationLevel != null || filters != null && filters.size() > 5)
                        throw invalid("Custom report options are invalid");
                    if (filters != null && !filters.isEmpty()) {
                        if (matchMode == null) matchMode = "all";
                        SegmentService.validateReportRules(matchMode, filters);
                    } else {
                        filters = List.of();
                        matchMode = "all";
                    }
                }
                default -> requireNull(
                        metric,
                        limit,
                        chartType,
                        dimension,
                        secondaryDimension,
                        locationLevel,
                        matchMode,
                        filters,
                        formula);
            }
            normalized.add(new Widget(
                    widget.id(),
                    widget.type(),
                    title,
                    metric,
                    limit,
                    chartType,
                    dimension,
                    secondaryDimension,
                    formula,
                    locationLevel,
                    matchMode,
                    filters));
        }
        return List.copyOf(normalized);
    }

    private static void requireNull(Object... values) {
        if (Arrays.stream(values).anyMatch(Objects::nonNull)) throw invalid("Widget options do not match its type");
    }

    private static boolean supportedReportDimension(String dimension) {
        if (dimension == null) return false;
        if (REPORT_DIMENSIONS.contains(dimension)) return true;
        String prefix = "custom:";
        return dimension.startsWith(prefix)
                && dimension
                        .substring(prefix.length())
                        .matches("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
    }

    private static String validateName(String name) {
        String normalized = name == null ? "" : name.strip();
        if (normalized.isBlank()
                || normalized.length() > 80
                || normalized.chars().anyMatch(Character::isISOControl))
            throw invalid("Dashboard names must contain 1 to 80 visible characters");
        return normalized;
    }

    private String serialize(List<Widget> widgets) {
        try {
            return mapper.writeValueAsString(widgets);
        } catch (Exception error) {
            throw new IllegalStateException("Could not serialize dashboard layout", error);
        }
    }

    private int count(Connection connection, UUID siteId, UUID userId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "select count(*) from analytics_dashboard_definition where site_id=? and user_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, userId);
            try (ResultSet row = statement.executeQuery()) {
                row.next();
                return row.getInt(1);
            }
        }
    }

    private boolean nameExists(Connection connection, UUID siteId, UUID userId, String name) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "select 1 from analytics_dashboard_definition where site_id=? and user_id=? and name=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, userId);
            statement.setString(3, name);
            try (ResultSet row = statement.executeQuery()) {
                return row.next();
            }
        }
    }

    private static void lockSite(Connection connection, UUID siteId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement("select id from site where id=? for update")) {
            statement.setObject(1, siteId);
            statement.executeQuery().close();
        }
    }

    private static void clearDefault(Connection connection, UUID siteId, UUID userId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "update analytics_dashboard_definition set is_default=false where site_id=? and user_id=? and is_default")) {
            statement.setObject(1, siteId);
            statement.setObject(2, userId);
            statement.executeUpdate();
        }
    }

    private static void promoteOldest(Connection connection, UUID siteId, UUID userId) throws SQLException {
        promoteOldest(connection, siteId, userId, null);
    }

    private static void promoteOldest(Connection connection, UUID siteId, UUID userId, UUID excludeId)
            throws SQLException {
        String sql = "select id from analytics_dashboard_definition where site_id=? and user_id=?"
                + (excludeId == null ? "" : " and id<>?") + " order by created_at,id limit 1";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, siteId);
            statement.setObject(2, userId);
            if (excludeId != null) statement.setObject(3, excludeId);
            try (ResultSet row = statement.executeQuery()) {
                if (row.next()) {
                    try (PreparedStatement promote = connection.prepareStatement(
                            "update analytics_dashboard_definition set is_default=true where id=?")) {
                        promote.setObject(1, row.getObject(1, UUID.class));
                        promote.executeUpdate();
                    }
                }
            }
        }
    }

    private static ControlPlaneException invalid(String message) {
        return new ControlPlaneException(400, "INVALID_DASHBOARD", message);
    }

    private static ControlPlaneException notFound() {
        return new ControlPlaneException(404, "DASHBOARD_NOT_FOUND", "Dashboard not found");
    }

    private static RuntimeException databaseError(String message, SQLException error) {
        if ("23505".equals(error.getSQLState()))
            return new ControlPlaneException(409, "DASHBOARD_NAME_EXISTS", "A dashboard with this name already exists");
        return new IllegalStateException(message, error);
    }

    public record Draft(String name, List<Widget> widgets, boolean isDefault) {}

    public record Widget(
            String id,
            String type,
            String title,
            String metric,
            Integer limit,
            String chartType,
            String dimension,
            String secondaryDimension,
            CustomReportService.Formula formula,
            String locationLevel,
            String matchMode,
            List<SegmentService.Rule> filters) {}

    public record View(
            UUID id, String name, List<Widget> widgets, boolean isDefault, Instant createdAt, Instant updatedAt) {}
}
