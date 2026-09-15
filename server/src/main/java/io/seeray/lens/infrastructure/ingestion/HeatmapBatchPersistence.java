package io.seeray.lens.infrastructure.ingestion;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.seeray.lens.application.HeatmapPayload;
import io.seeray.lens.application.TrackingSanitizer;
import io.seeray.lens.domain.common.UuidV7;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.util.UUID;
import org.hibernate.Session;

/** A dedicated raw store keeps high-frequency heatmap data out of raw_event and normal analytics. */
@ApplicationScoped
public class HeatmapBatchPersistence {
    private final EntityManager entityManager;
    private final ObjectMapper mapper;

    @Inject
    public HeatmapBatchPersistence(EntityManager entityManager, ObjectMapper mapper) {
        this.entityManager = entityManager;
        this.mapper = mapper;
    }

    @Transactional
    public boolean persist(UUID siteId, int effectiveSampleRate, HeatmapPayload payload) {
        try {
            UUID batchId = UUID.fromString(payload.clientBatchId());
            ArrayNode events = mapper.valueToTree(payload.events());
            for (var node : events) {
                ObjectNode event = (ObjectNode) node;
                TrackingSanitizer.CleanUrl url =
                        TrackingSanitizer.url(event.path("url").asText(), mapper);
                event.put("url", url.scheme() + "://" + url.host() + url.path());
            }
            String body = mapper.writeValueAsString(events);
            final int[] updated = {0};
            entityManager.unwrap(Session.class).doWork(connection -> {
                try (var statement = connection.prepareStatement(
                        """
                        INSERT INTO heatmap_raw_batch (id, site_id, client_batch_id, received_at, effective_sample_rate, payload)
                        VALUES (?, ?, ?, now(), ?, ?::jsonb)
                        ON CONFLICT (site_id, client_batch_id) DO NOTHING
                        """)) {
                    statement.setObject(1, UuidV7.next());
                    statement.setObject(2, siteId);
                    statement.setObject(3, batchId);
                    statement.setInt(4, effectiveSampleRate);
                    statement.setString(5, body);
                    updated[0] = statement.executeUpdate();
                }
            });
            return updated[0] == 1;
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to persist heatmap batch", exception);
        }
    }
}
