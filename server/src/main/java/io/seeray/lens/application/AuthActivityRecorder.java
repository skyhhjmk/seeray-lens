package io.seeray.lens.application;

import io.seeray.lens.domain.common.UuidV7;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import javax.sql.DataSource;
import org.jboss.logging.Logger;

/** Stores minimal authentication outcomes against each workspace membership at event time. */
@ApplicationScoped
public class AuthActivityRecorder {
    private static final Logger LOG = Logger.getLogger(AuthActivityRecorder.class);
    private static final Set<String> EVENTS =
            Set.of("LOGIN_SUCCEEDED", "LOGIN_FAILED", "SESSION_REFRESHED", "LOGOUT", "REFRESH_REJECTED");

    private final DataSource dataSource;

    public AuthActivityRecorder(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Transactional(Transactional.TxType.REQUIRES_NEW)
    public void record(UUID actorUserId, String eventType) {
        if (actorUserId == null || !EVENTS.contains(eventType)) return;
        Instant occurredAt = Instant.now();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement memberships = connection.prepareStatement(
                        "select organization_id from organization_member where user_id=?")) {
            memberships.setObject(1, actorUserId);
            try (ResultSet rows = memberships.executeQuery()) {
                List<UUID> organizations = new ArrayList<>();
                while (rows.next()) organizations.add(rows.getObject(1, UUID.class));
                try (PreparedStatement insert = connection.prepareStatement(
                        "insert into workspace_auth_activity(id,organization_id,actor_user_id,event_type,created_at) "
                                + "values(?,?,?,?,?)")) {
                    for (UUID organizationId : organizations) {
                        insert.setObject(1, UuidV7.next());
                        insert.setObject(2, organizationId);
                        insert.setObject(3, actorUserId);
                        insert.setString(4, eventType);
                        insert.setTimestamp(5, Timestamp.from(occurredAt));
                        insert.addBatch();
                    }
                    insert.executeBatch();
                }
            }
        } catch (SQLException error) {
            // Authentication must keep its normal outcome if the best-effort audit sink is unavailable.
            LOG.warn("Could not persist workspace authentication activity", error);
        }
    }
}
