package io.seeray.lens.infrastructure.ingestion;

import io.quarkus.scheduler.Scheduled;
import io.seeray.lens.application.HeatmapAggregationService;
import jakarta.enterprise.context.ApplicationScoped;
import org.jboss.logging.Logger;

@ApplicationScoped
public class HeatmapAggregationWorker {
    private static final Logger LOG = Logger.getLogger(HeatmapAggregationWorker.class);
    private final HeatmapAggregationService aggregation;

    public HeatmapAggregationWorker(HeatmapAggregationService aggregation) {
        this.aggregation = aggregation;
    }

    @Scheduled(every = "1s", identity = "heatmap-aggregation")
    void process() {
        int processed = aggregation.processPending(100);
        if (processed > 0) LOG.infof("Aggregated %d heatmap batches", processed);
    }
}
