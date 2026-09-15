package io.seeray.lens.infrastructure.ingestion;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.HeatmapMessage;
import io.smallrye.reactive.messaging.annotations.Blocking;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.concurrent.CompletionStage;
import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.eclipse.microprofile.reactive.messaging.Message;

@ApplicationScoped
public class HeatmapIngestionWorker {
    private final ObjectMapper mapper;
    private final HeatmapBatchPersistence persistence;

    public HeatmapIngestionWorker(ObjectMapper mapper, HeatmapBatchPersistence persistence) {
        this.mapper = mapper;
        this.persistence = persistence;
    }

    @Incoming("heatmap-in")
    @Blocking
    public CompletionStage<Void> consume(Message<?> message) {
        try {
            HeatmapMessage payload = mapper.readValue(String.valueOf(message.getPayload()), HeatmapMessage.class);
            persistence.persist(payload.siteId(), payload.effectiveSampleRate(), payload.payload());
            return message.ack();
        } catch (Exception error) {
            return message.nack(error);
        }
    }
}
