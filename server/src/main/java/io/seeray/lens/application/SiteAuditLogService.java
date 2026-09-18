package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.enterprise.context.ApplicationScoped;
import java.sql.*;
import java.time.*;
import java.time.format.DateTimeParseException;
import java.util.*;
import javax.sql.DataSource;

@ApplicationScoped
public class SiteAuditLogService {
    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;

    public SiteAuditLogService(DataSource dataSource, SiteService sites, WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
    }

    public Page list(UUID siteId, String fromValue, String toValue, String cursorValue, int requestedLimit) {
        var site = sites.site(siteId);
        access.member(site.organization.id);
        ZoneId zone = ZoneId.of(site.timezone);
        LocalDate today = LocalDate.now(zone);
        LocalDate from = parseDate(fromValue, today.minusDays(29));
        LocalDate to = parseDate(toValue, today);
        if (from.isAfter(to) || from.plusDays(365).isBefore(to))
            throw new ControlPlaneException(400, "AUDIT_RANGE_INVALID", "Choose a date range of at most 366 days");
        int limit = Math.max(1, Math.min(requestedLimit, 100));
        Cursor cursor = parseCursor(cursorValue);
        String sql = "select l.id,l.actor_user_id,u.email,l.action,l.resource,l.resource_id,l.created_at,"
                + "l.actor_api_token_id,t.name "
                + "from site_audit_log l left join app_user u on u.id=l.actor_user_id "
                + "left join api_token t on t.id=l.actor_api_token_id "
                + "where l.site_id=? and l.created_at>=? and l.created_at<? "
                + (cursor == null ? "" : "and (l.created_at<? or (l.created_at=? and l.id<?)) ")
                + "order by l.created_at desc,l.id desc limit ?";
        List<Entry> entries = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = 1;
            statement.setObject(index++, siteId);
            statement.setTimestamp(
                    index++, Timestamp.from(from.atStartOfDay(zone).toInstant()));
            statement.setTimestamp(
                    index++, Timestamp.from(to.plusDays(1).atStartOfDay(zone).toInstant()));
            if (cursor != null) {
                statement.setTimestamp(index++, Timestamp.from(cursor.createdAt()));
                statement.setTimestamp(index++, Timestamp.from(cursor.createdAt()));
                statement.setObject(index++, cursor.id());
            }
            statement.setInt(index, limit + 1);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    entries.add(new Entry(
                            rows.getObject(1, UUID.class),
                            rows.getObject(2, UUID.class),
                            rows.getString(3),
                            rows.getString(4),
                            rows.getString(5),
                            rows.getObject(6, UUID.class),
                            rows.getTimestamp(7).toInstant(),
                            rows.getObject(8, UUID.class),
                            rows.getString(9)));
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read site audit history", error);
        }
        String nextCursor = null;
        if (entries.size() > limit) {
            entries.remove(entries.size() - 1);
            Entry last = entries.get(entries.size() - 1);
            nextCursor = last.createdAt() + "|" + last.id();
        }
        return new Page(from, to, List.copyOf(entries), nextCursor);
    }

    private static LocalDate parseDate(String value, LocalDate fallback) {
        if (value == null || value.isBlank()) return fallback;
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException error) {
            throw new ControlPlaneException(400, "AUDIT_RANGE_INVALID", "Dates must use YYYY-MM-DD format");
        }
    }

    private static Cursor parseCursor(String value) {
        if (value == null || value.isBlank()) return null;
        try {
            int separator = value.lastIndexOf('|');
            return new Cursor(
                    Instant.parse(value.substring(0, separator)), UUID.fromString(value.substring(separator + 1)));
        } catch (RuntimeException error) {
            throw new ControlPlaneException(400, "AUDIT_CURSOR_INVALID", "The audit page cursor is invalid");
        }
    }

    private record Cursor(Instant createdAt, UUID id) {}

    public record Entry(
            UUID id,
            UUID actorUserId,
            String actorEmail,
            String action,
            String resource,
            UUID resourceId,
            Instant createdAt,
            UUID actorApiTokenId,
            String actorApiTokenName) {}

    public record Page(LocalDate from, LocalDate to, List<Entry> entries, String nextCursor) {}
}
