package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import java.sql.*;
import java.time.*;
import java.time.format.DateTimeParseException;
import java.util.*;
import javax.sql.DataSource;

@ApplicationScoped
public class WorkspaceAuditLogService {
    private final DataSource dataSource;
    private final WorkspaceAccess access;

    public WorkspaceAuditLogService(DataSource dataSource, WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.access = access;
    }

    public Page list(UUID workspaceId, String fromValue, String toValue, String cursorValue, int requestedLimit) {
        access.require(workspaceId, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        LocalDate from = parseDate(fromValue, today.minusDays(29));
        LocalDate to = parseDate(toValue, today);
        if (from.isAfter(to) || from.plusDays(365).isBefore(to)) {
            throw new ControlPlaneException(400, "AUDIT_RANGE_INVALID", "Choose a date range of at most 366 days");
        }
        int limit = Math.max(1, Math.min(requestedLimit, 100));
        Cursor cursor = parseCursor(cursorValue);
        String sql = "select l.id,l.actor_user_id,u.email,l.action,l.resource,l.resource_id,l.created_at "
                + "from workspace_audit_log l left join app_user u on u.id=l.actor_user_id "
                + "where l.organization_id=? and l.created_at>=? and l.created_at<? "
                + (cursor == null ? "" : "and (l.created_at<? or (l.created_at=? and l.id<?)) ")
                + "order by l.created_at desc,l.id desc limit ?";
        List<Entry> entries = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = 1;
            statement.setObject(index++, workspaceId);
            statement.setTimestamp(
                    index++, Timestamp.from(from.atStartOfDay(ZoneOffset.UTC).toInstant()));
            statement.setTimestamp(
                    index++,
                    Timestamp.from(to.plusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant()));
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
                            rows.getTimestamp(7).toInstant()));
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read workspace activity", error);
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
            throw new ControlPlaneException(400, "AUDIT_CURSOR_INVALID", "The activity page cursor is invalid");
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
            Instant createdAt) {}

    public record Page(LocalDate from, LocalDate to, List<Entry> entries, String nextCursor) {}
}
