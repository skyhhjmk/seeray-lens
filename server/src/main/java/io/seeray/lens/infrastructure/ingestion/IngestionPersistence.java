package io.seeray.lens.infrastructure.ingestion;

import io.seeray.lens.application.TrackingMessage;
import io.seeray.lens.application.TrackingSanitizer.CleanUrl;
import io.seeray.lens.application.WorkspaceExtensionDeliveryService;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.sql.Types;
import java.util.List;
import org.hibernate.Session;

@ApplicationScoped
public class IngestionPersistence {
    private final EntityManager entityManager;
    private final WorkspaceExtensionDeliveryService extensionDeliveries;

    @Inject
    public IngestionPersistence(EntityManager entityManager, WorkspaceExtensionDeliveryService extensionDeliveries) {
        this.entityManager = entityManager;
        this.extensionDeliveries = extensionDeliveries;
    }

    @Transactional
    public void persistBatch(List<TrackingMessage> events) {
        entityManager.unwrap(Session.class).doWork(connection -> {
            try (var statement = connection.prepareStatement(
                    """
                    INSERT INTO raw_event (ingest_id, site_id, client_event_id, client_visitor_id, client_session_id, received_at, occurred_at, event_type,
                      page_scheme, page_host, page_path, page_title, referrer_scheme, referrer_host, referrer_path,
                      utm_source, utm_medium, utm_campaign, utm_term, utm_content, ad_click_platform, ad_click_id_hash,
                      event_data, duration_ms, user_id_hash, ingest_version, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb, ?, ?, 1, now())
                    ON CONFLICT (site_id, client_event_id) DO NOTHING""")) {
                for (TrackingMessage event : events) {
                    statement.setObject(1, event.ingestId());
                    statement.setObject(2, event.siteId());
                    statement.setObject(3, event.clientEventId());
                    statement.setString(4, event.visitorId());
                    statement.setString(5, event.sessionId());
                    statement.setTimestamp(6, java.sql.Timestamp.from(event.receivedAt()));
                    statement.setTimestamp(7, java.sql.Timestamp.from(event.occurredAt()));
                    statement.setString(8, event.eventType());
                    setPage(statement, 9, event.page());
                    setPage(statement, 13, event.referrer());
                    statement.setString(
                            16, event.page() == null ? null : event.page().source());
                    statement.setString(
                            17, event.page() == null ? null : event.page().medium());
                    statement.setString(
                            18, event.page() == null ? null : event.page().campaign());
                    statement.setString(
                            19, event.page() == null ? null : event.page().term());
                    statement.setString(
                            20, event.page() == null ? null : event.page().content());
                    statement.setString(
                            21, event.page() == null ? null : event.page().adClickPlatform());
                    statement.setString(
                            22, event.page() == null ? null : event.page().adClickIdHash());
                    statement.setString(23, event.eventData());
                    if (event.durationMs() == null) statement.setNull(24, Types.INTEGER);
                    else statement.setInt(24, event.durationMs());
                    statement.setString(25, event.userIdHash());
                    statement.addBatch();
                }
                statement.executeBatch();
            }
        });
        extensionDeliveries.enqueue(events);
    }

    private static void setPage(java.sql.PreparedStatement s, int start, CleanUrl p) throws java.sql.SQLException {
        if (p == null) {
            s.setNull(start, Types.VARCHAR);
            s.setNull(start + 1, Types.VARCHAR);
            s.setNull(start + 2, Types.VARCHAR);
            s.setNull(start + 3, Types.VARCHAR);
        } else {
            s.setString(start, p.scheme());
            s.setString(start + 1, p.host());
            s.setString(start + 2, p.path());
            s.setString(start + 3, p.title());
        }
    }
}
