package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.Instant;
import java.time.ZoneId;
import java.util.*;
import javax.sql.DataSource;

/** Manages named event properties and their site-scoped reports. */
@ApplicationScoped
public class CustomDimensionService {
    private static final int MAX_DIMENSIONS_PER_SITE = 20;

    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final SegmentService segments;

    @Inject
    public CustomDimensionService(
            DataSource dataSource, SiteService sites, WorkspaceAccess access, SegmentService segments) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
        this.segments = segments;
    }

    public List<Definition> list(UUID siteId) {
        Site site = readableSite(siteId);
        String sql = "select id,dimension_key,name,description,enabled,created_at,updated_at "
                + "from custom_dimension_definition where site_id=? order by name,id";
        List<Definition> result = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, site.id);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) result.add(definition(rows));
            }
            return result;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list custom dimensions", error);
        }
    }

    @Transactional
    public Definition create(UUID siteId, Update update) {
        Site site = writableSite(siteId);
        validate(update);
        try (Connection connection = dataSource.getConnection()) {
            try (PreparedStatement count =
                    connection.prepareStatement("select count(*) from custom_dimension_definition where site_id=?")) {
                count.setObject(1, siteId);
                try (ResultSet row = count.executeQuery()) {
                    row.next();
                    if (row.getInt(1) >= MAX_DIMENSIONS_PER_SITE)
                        throw new ControlPlaneException(
                                409, "DIMENSION_LIMIT_REACHED", "A site can have at most 20 custom dimensions");
                }
            }
            UUID id = UuidV7.next();
            Instant now = Instant.now();
            try (PreparedStatement insert = connection.prepareStatement(
                    "insert into custom_dimension_definition(id,site_id,dimension_key,name,description,enabled,created_at,updated_at) values(?,?,?,?,?,?,?,?)")) {
                bind(insert, id, siteId, update, now);
                insert.executeUpdate();
            }
            return get(connection, siteId, id);
        } catch (SQLException error) {
            if ("23505".equals(error.getSQLState()))
                throw new ControlPlaneException(
                        409, "DIMENSION_KEY_EXISTS", "A dimension with this key already exists");
            throw new IllegalStateException("Could not create custom dimension", error);
        }
    }

    @Transactional
    public Definition update(UUID siteId, UUID dimensionId, Update update) {
        writableSite(siteId);
        validate(update);
        String sql =
                "update custom_dimension_definition set dimension_key=?,name=?,description=?,enabled=?,updated_at=? "
                        + "where site_id=? and id=?";
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            Definition current = get(connection, siteId, dimensionId);
            if (!current.key().equals(update.key().trim()))
                throw new ControlPlaneException(
                        400, "DIMENSION_KEY_IMMUTABLE", "Create a new dimension to change its property key");
            statement.setString(1, update.key().trim());
            statement.setString(2, update.name().trim());
            statement.setString(
                    3, update.description() == null ? "" : update.description().trim());
            statement.setBoolean(4, update.enabled());
            statement.setTimestamp(5, Timestamp.from(Instant.now()));
            statement.setObject(6, siteId);
            statement.setObject(7, dimensionId);
            if (statement.executeUpdate() == 0) throw notFound();
            return get(connection, siteId, dimensionId);
        } catch (SQLException error) {
            if ("23505".equals(error.getSQLState()))
                throw new ControlPlaneException(
                        409, "DIMENSION_KEY_EXISTS", "A dimension with this key already exists");
            throw new IllegalStateException("Could not update custom dimension", error);
        }
    }

    @Transactional
    public void delete(UUID siteId, UUID dimensionId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "delete from custom_dimension_definition where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, dimensionId);
            if (statement.executeUpdate() == 0) throw notFound();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not delete custom dimension", error);
        }
    }

    public List<Value> report(UUID siteId, UUID dimensionId, AnalyticsQueryService.Range range, int requestedLimit) {
        return report(siteId, dimensionId, range, requestedLimit, null);
    }

    public List<Value> report(
            UUID siteId, UUID dimensionId, AnalyticsQueryService.Range range, int requestedLimit, UUID segmentId) {
        Site site = readableSite(siteId);
        Definition dimension;
        try (Connection connection = dataSource.getConnection()) {
            dimension = get(connection, siteId, dimensionId);
            if (!dimension.enabled()) return List.of();
            if (segmentId != null) return segmentedReport(siteId, site, dimension, range, requestedLimit, segmentId);
            String sql =
                    "select dimension_value.value,count(*),count(distinct e.client_session_id),count(distinct e.client_visitor_id) "
                            + "from raw_event e cross join lateral (select e.event_data #>> ARRAY['data',cast(? as text)] as value, "
                            + "e.event_data #> ARRAY['data',cast(? as text)] as raw_value) dimension_value "
                            + "where e.site_id=? and e.occurred_at>=? and e.occurred_at<? "
                            + "and jsonb_typeof(dimension_value.raw_value) in ('string','number','boolean') "
                            + "group by dimension_value.value order by count(*) desc,dimension_value.value asc limit ?";
            List<Value> result = new ArrayList<>();
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                statement.setString(1, dimension.key());
                statement.setString(2, dimension.key());
                statement.setObject(3, siteId);
                ZoneId zone = ZoneId.of(site.timezone);
                statement.setTimestamp(
                        4, Timestamp.from(range.from().atStartOfDay(zone).toInstant()));
                statement.setTimestamp(
                        5,
                        Timestamp.from(range.to().plusDays(1).atStartOfDay(zone).toInstant()));
                statement.setInt(6, Math.max(1, Math.min(requestedLimit, 100)));
                try (ResultSet rows = statement.executeQuery()) {
                    while (rows.next())
                        result.add(new Value(rows.getString(1), rows.getLong(2), rows.getLong(3), rows.getLong(4)));
                }
            }
            return result;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query custom dimension report", error);
        }
    }

    private List<Value> segmentedReport(
            UUID siteId,
            Site site,
            Definition dimension,
            AnalyticsQueryService.Range range,
            int requestedLimit,
            UUID segmentId) {
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        String eventTime = "(case when e.occurred_at < e.received_at - interval '24 hours' "
                + "or e.occurred_at > e.received_at + interval '24 hours' then e.received_at else e.occurred_at end)";
        String sql =
                "with matching_sessions as (select s.id,s.site_id,s.visitor_id,v.client_visitor_id,s.client_session_id,"
                        + "s.started_at,s.last_activity_at from analytics_session s "
                        + "join analytics_visitor v on v.id=s.visitor_id and v.site_id=s.site_id "
                        + "where s.site_id=? and (s.started_at at time zone ?)::date between ? and ? and ("
                        + filter.expression() + ")) "
                        + "select dimension_value.value,count(*),count(distinct ms.id),count(distinct ms.visitor_id) "
                        + "from matching_sessions ms join raw_event e on e.site_id=ms.site_id "
                        + "and e.client_session_id=ms.client_session_id and e.client_visitor_id=ms.client_visitor_id "
                        + "and " + eventTime + " between ms.started_at and ms.last_activity_at "
                        + "cross join lateral (select e.event_data #>> ARRAY['data',cast(? as text)] as value, "
                        + "e.event_data #> ARRAY['data',cast(? as text)] as raw_value) dimension_value "
                        + "where (" + eventTime + " at time zone ?)::date between ? and ? "
                        + "and jsonb_typeof(dimension_value.raw_value) in ('string','number','boolean') "
                        + "group by dimension_value.value order by count(*) desc,dimension_value.value asc limit ?";
        List<Value> result = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = 1;
            statement.setObject(index++, siteId);
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            for (Object value : filter.values()) statement.setObject(index++, value);
            statement.setString(index++, dimension.key());
            statement.setString(index++, dimension.key());
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            statement.setInt(index, Math.max(1, Math.min(requestedLimit, 100)));
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next())
                    result.add(new Value(rows.getString(1), rows.getLong(2), rows.getLong(3), rows.getLong(4)));
            }
            return result;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query segmented custom dimension report", error);
        }
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

    private static Definition get(Connection connection, UUID siteId, UUID dimensionId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "select id,dimension_key,name,description,enabled,created_at,updated_at from custom_dimension_definition where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, dimensionId);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) throw notFound();
                return definition(rows);
            }
        }
    }

    private static Definition definition(ResultSet rows) throws SQLException {
        return new Definition(
                rows.getObject(1, UUID.class),
                rows.getString(2),
                rows.getString(3),
                rows.getString(4),
                rows.getBoolean(5),
                rows.getTimestamp(6).toInstant(),
                rows.getTimestamp(7).toInstant());
    }

    private static void bind(PreparedStatement statement, UUID id, UUID siteId, Update update, Instant now)
            throws SQLException {
        statement.setObject(1, id);
        statement.setObject(2, siteId);
        statement.setString(3, update.key().trim());
        statement.setString(4, update.name().trim());
        statement.setString(
                5, update.description() == null ? "" : update.description().trim());
        statement.setBoolean(6, update.enabled());
        statement.setTimestamp(7, Timestamp.from(now));
        statement.setTimestamp(8, Timestamp.from(now));
    }

    private static void validate(Update update) {
        if (update == null
                || update.key() == null
                || !update.key().trim().matches("[a-z][a-z0-9_]{0,63}")
                || update.name() == null
                || update.name().isBlank()
                || update.name().trim().length() > 128
                || update.description() != null && update.description().length() > 512)
            throw new ControlPlaneException(
                    400, "INVALID_CUSTOM_DIMENSION", "Dimension name, key, or description is invalid");
    }

    private static ControlPlaneException notFound() {
        return new ControlPlaneException(404, "DIMENSION_NOT_FOUND", "Custom dimension was not found");
    }

    public record Update(String key, String name, String description, boolean enabled) {}

    public record Definition(
            UUID id,
            String key,
            String name,
            String description,
            boolean enabled,
            Instant createdAt,
            Instant updatedAt) {}

    public record Value(String value, long events, long sessions, long visitors) {}
}
