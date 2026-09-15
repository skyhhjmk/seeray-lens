package io.seeray.lens.infrastructure.ingestion;

import io.quarkus.scheduler.Scheduled;
import io.seeray.lens.application.HeatmapFileCleanupService;
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class HeatmapFileCleanupWorker {
    private final HeatmapFileCleanupService cleanup;

    public HeatmapFileCleanupWorker(HeatmapFileCleanupService cleanup) {
        this.cleanup = cleanup;
    }

    @Scheduled(every = "1m", identity = "heatmap-file-cleanup")
    void clean() {
        cleanup.process(100);
    }
}
