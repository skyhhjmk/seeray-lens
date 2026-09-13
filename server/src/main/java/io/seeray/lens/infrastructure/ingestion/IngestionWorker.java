package io.seeray.lens.infrastructure.ingestion;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.TrackingMessage;
import io.smallrye.reactive.messaging.annotations.Blocking;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.*;
import java.util.concurrent.*;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.eclipse.microprofile.reactive.messaging.Message;
import org.jboss.logging.Logger;

@ApplicationScoped
public class IngestionWorker {
    private static final Logger LOG = Logger.getLogger(IngestionWorker.class);
    private final ObjectMapper mapper;
    private final IngestionPersistence persistence;
    private final int maxBatchSize;
    private final List<Pending> pending = new ArrayList<>();
    private final Object lock = new Object();

    @Inject
    public IngestionWorker(
            ObjectMapper mapper,
            IngestionPersistence persistence,
            @ConfigProperty(name = "seeray.ingestion.max-batch-size", defaultValue = "500") int maxBatchSize) {
        this.mapper = mapper;
        this.persistence = persistence;
        this.maxBatchSize = maxBatchSize;
    }

    @Incoming("tracking-in")
    @Blocking
    public CompletionStage<Void> consume(Message<?> message) {
        LOG.infof(
                "Received tracking message (%d bytes)",
                message.getPayload() == null
                        ? 0
                        : message.getPayload().toString().length());
        CompletableFuture<Void> completion = new CompletableFuture<>();
        boolean flush;
        synchronized (lock) {
            pending.add(new Pending(message, completion));
            flush = pending.size() >= maxBatchSize;
        }
        if (flush) flush();
        return completion;
    }

    @io.quarkus.scheduler.Scheduled(every = "1s", identity = "tracking-ingestion-flush")
    void scheduledFlush() {
        flush();
    }

    void flush() {
        List<Pending> batch;
        synchronized (lock) {
            if (pending.isEmpty()) return;
            batch = new ArrayList<>(pending);
            pending.clear();
        }
        try {
            List<TrackingMessage> events = new ArrayList<>(batch.size());
            for (Pending item : batch)
                events.add(mapper.readValue(String.valueOf(item.message.getPayload()), TrackingMessage.class));
            persistence.persistBatch(events);
            for (Pending item : batch) item.completion.complete(null);
            for (Pending item : batch) item.message.ack();
        } catch (Exception error) {
            LOG.error("Tracking batch failed; messages will be rejected", error);
            for (Pending item : batch) item.completion.completeExceptionally(error);
        }
    }

    private record Pending(Message<?> message, CompletableFuture<Void> completion) {}
}
