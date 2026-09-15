package io.seeray.lens.infrastructure.ingestion;

import io.quarkus.scheduler.Scheduled;
import io.seeray.lens.application.HeatmapRetentionService;
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class HeatmapRetentionWorker {
    private final HeatmapRetentionService retention;

    public HeatmapRetentionWorker(HeatmapRetentionService retention) {
        this.retention = retention;
    }

    @Scheduled(cron = "0 17 3 * * ?", identity = "heatmap-retention")
    void clean() {
        retention.clean();
    }
}
