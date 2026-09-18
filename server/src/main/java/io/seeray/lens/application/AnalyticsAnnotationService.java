package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.*;
import java.time.format.DateTimeParseException;
import java.util.*;
import javax.sql.DataSource;

/** Site-scoped notes attached to local analytics dates. */
@ApplicationScoped
public class AnalyticsAnnotationService {
    private static final int MAX_RANGE_DAYS = 366;
    private static final int MAX_NOTE_LENGTH = 500;

    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;

    public AnalyticsAnnotationService(DataSource dataSource, SiteService sites, WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
    }

    public ListResponse list(UUID siteId, String fromValue, String toValue) {
        Site site = sites.site(siteId);
        var member = access.member(site.organization.id);
        ZoneId zone = ZoneId.of(site.timezone);
        LocalDate today = LocalDate.now(zone);
        LocalDate from = parseRangeDate(fromValue, today.minusDays(29));
        LocalDate to = parseRangeDate(toValue, today);
        validateRange(from, to);
        List<AnnotationView> entries = new ArrayList<>();
        String sql = "select id,annotation_date,note,actor_user_id,created_at,updated_at "
                + "from analytics_annotation where site_id=? and annotation_date between ? and ? "
                + "order by annotation_date desc,created_at desc,id desc";
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, siteId);
            statement.setObject(2, from);
            statement.setObject(3, to);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) entries.add(read(rows));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list analytics annotations", error);
        }
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        return new ListResponse(from, to, List.copyOf(entries), canManage);
    }

    @Transactional
    public AnnotationView create(UUID siteId, Update update) {
        Site site = writableSite(siteId);
        Normalized normalized = normalize(update);
        UUID id = UuidV7.next();
        String sql =
                "insert into analytics_annotation(id,site_id,annotation_date,note,actor_user_id) values(?,?,?,?,?)";
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, id);
            statement.setObject(2, siteId);
            statement.setObject(3, normalized.date());
            statement.setString(4, normalized.note());
            statement.setObject(5, access.userId());
            statement.executeUpdate();
            return get(connection, siteId, id);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not create analytics annotation", error);
        }
    }

    @Transactional
    public AnnotationView update(UUID siteId, UUID annotationId, Update update) {
        Site site = writableSite(siteId);
        Normalized normalized = normalize(update);
        String sql = "update analytics_annotation set annotation_date=?,note=?,actor_user_id=?,updated_at=now() "
                + "where site_id=? and id=?";
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, normalized.date());
            statement.setString(2, normalized.note());
            statement.setObject(3, access.userId());
            statement.setObject(4, siteId);
            statement.setObject(5, annotationId);
            if (statement.executeUpdate() == 0) throw notFound();
            return get(connection, siteId, annotationId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not update analytics annotation", error);
        }
    }

    @Transactional
    public void delete(UUID siteId, UUID annotationId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement =
                        connection.prepareStatement("delete from analytics_annotation where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, annotationId);
            if (statement.executeUpdate() == 0) throw notFound();
        } catch (SQLException error) {
            throw new IllegalStateException("Could not delete analytics annotation", error);
        }
    }

    private AnnotationView get(Connection connection, UUID siteId, UUID id) throws SQLException {
        try (PreparedStatement statement =
                connection.prepareStatement("select id,annotation_date,note,actor_user_id,created_at,updated_at "
                        + "from analytics_annotation where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, id);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) throw notFound();
                return read(rows);
            }
        }
    }

    private static AnnotationView read(ResultSet rows) throws SQLException {
        return new AnnotationView(
                rows.getObject(1, UUID.class),
                rows.getObject(2, LocalDate.class),
                rows.getString(3),
                rows.getObject(4, UUID.class),
                rows.getTimestamp(5).toInstant(),
                rows.getTimestamp(6).toInstant());
    }

    private Site writableSite(UUID siteId) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return site;
    }

    private static Normalized normalize(Update update) {
        if (update == null) throw invalid();
        if (update.date() == null || update.date().isBlank()) throw invalid();
        LocalDate date = parseDate(update.date(), null);
        String note = update.note() == null ? "" : update.note().trim();
        if (note.isEmpty() || note.length() > MAX_NOTE_LENGTH) throw invalid();
        return new Normalized(date, note);
    }

    private static LocalDate parseDate(String value, LocalDate fallback) {
        if (value == null || value.isBlank()) return fallback;
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException error) {
            throw invalid();
        }
    }

    private static LocalDate parseRangeDate(String value, LocalDate fallback) {
        if (value == null || value.isBlank()) return fallback;
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException error) {
            throw new ControlPlaneException(400, "ANNOTATION_RANGE_INVALID", "Dates must use YYYY-MM-DD format");
        }
    }

    private static void validateRange(LocalDate from, LocalDate to) {
        if (from.isAfter(to) || from.plusDays(MAX_RANGE_DAYS - 1).isBefore(to))
            throw new ControlPlaneException(400, "ANNOTATION_RANGE_INVALID", "Choose a date range of at most 366 days");
    }

    private static ControlPlaneException notFound() {
        return new ControlPlaneException(404, "ANNOTATION_NOT_FOUND", "Analytics annotation not found");
    }

    private static ControlPlaneException invalid() {
        return new ControlPlaneException(
                400, "ANNOTATION_INVALID", "Provide a valid date and a note of 1 to 500 characters");
    }

    private record Normalized(LocalDate date, String note) {}

    public record Update(String date, String note) {}

    public record AnnotationView(
            UUID id, LocalDate date, String note, UUID actorUserId, Instant createdAt, Instant updatedAt) {}

    public record ListResponse(LocalDate from, LocalDate to, List<AnnotationView> annotations, boolean canManage) {}
}
