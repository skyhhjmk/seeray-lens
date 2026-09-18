package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import javax.sql.DataSource;

/** Read-only, owner-scoped recent API request history for workspace tokens. */
@ApplicationScoped
public class ApiTokenUsageService {
    public static final int RETENTION_DAYS = 30;
    private static final int DEFAULT_LIMIT = 25;
    private static final int MAX_LIMIT = 100;

    private final DataSource dataSource;
    private final WorkspaceAccess access;

    public ApiTokenUsageService(DataSource dataSource, WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.access = access;
    }

    public Page list(UUID workspaceId, UUID tokenId, String cursorValue, int requestedLimit) {
        access.require(workspaceId, WorkspaceRole.OWNER);
        int limit = Math.max(1, Math.min(requestedLimit <= 0 ? DEFAULT_LIMIT : requestedLimit, MAX_LIMIT));
        Cursor cursor = parseCursor(cursorValue);
        List<Entry> entries = new ArrayList<>();
        String sql = "select id,method,route_template,status_code,created_at from api_token_request_log "
                + "where token_id=? and created_at>=now()-interval '" + RETENTION_DAYS + " days' "
                + (cursor == null ? "" : "and (created_at<? or (created_at=? and id<?)) ")
                + "order by created_at desc,id desc limit ?";
        try (Connection connection = dataSource.getConnection()) {
            try (PreparedStatement exists =
                    connection.prepareStatement("select 1 from api_token where id=? and organization_id=?")) {
                exists.setObject(1, tokenId);
                exists.setObject(2, workspaceId);
                try (ResultSet row = exists.executeQuery()) {
                    if (!row.next()) throw notFound();
                }
            }
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                int index = 1;
                statement.setObject(index++, tokenId);
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
                                rows.getString(2),
                                rows.getString(3),
                                rows.getInt(4),
                                rows.getTimestamp(5).toInstant()));
                    }
                }
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read API token activity", error);
        }
        String nextCursor = null;
        if (entries.size() > limit) {
            entries.remove(entries.size() - 1);
            Entry last = entries.get(entries.size() - 1);
            nextCursor = last.createdAt() + "|" + last.id();
        }
        return new Page(List.copyOf(entries), nextCursor, RETENTION_DAYS);
    }

    private static Cursor parseCursor(String value) {
        if (value == null || value.isBlank()) return null;
        try {
            int separator = value.lastIndexOf('|');
            return new Cursor(
                    Instant.parse(value.substring(0, separator)), UUID.fromString(value.substring(separator + 1)));
        } catch (RuntimeException error) {
            throw new ControlPlaneException(400, "API_TOKEN_CURSOR_INVALID", "The activity page cursor is invalid");
        }
    }

    private static ControlPlaneException notFound() {
        return new ControlPlaneException(404, "API_TOKEN_NOT_FOUND", "API token not found");
    }

    private record Cursor(Instant createdAt, UUID id) {}

    public record Entry(UUID id, String method, String routeTemplate, int statusCode, Instant createdAt) {}

    public record Page(List<Entry> entries, String nextCursor, int retentionDays) {}
}
