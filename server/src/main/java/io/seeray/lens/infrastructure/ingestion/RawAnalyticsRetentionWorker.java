package io.seeray.lens.infrastructure.ingestion;

import io.quarkus.scheduler.Scheduled;
import io.seeray.lens.application.RawAnalyticsRetentionService;
import jakarta.enterprise.context.ApplicationScoped;
import org.jboss.logging.Logger;

@ApplicationScoped
public class RawAnalyticsRetentionWorker {
    private static final Logger LOG = Logger.getLogger(RawAnalyticsRetentionWorker.class);
    private final RawAnalyticsRetentionService retention;

    public RawAnalyticsRetentionWorker(RawAnalyticsRetentionService retention) {
        this.retention = retention;
    }

    @Scheduled(cron = "0 47 3 * * ?", identity = "analytics-raw-retention")
    void clean() {
        try {
            RawAnalyticsRetentionService.CleanupSummary summary = retention.clean();
            LOG.infof(
                    "Analytics retention processed %d sites; deleted %d raw events, %d aggregate rows, %d sessions, and %d visitors",
                    summary.sitesProcessed(),
                    summary.rawEventsDeleted(),
                    summary.aggregateRowsDeleted(),
                    summary.sessionsDeleted(),
                    summary.visitorsDeleted());
        } catch (Exception failure) {
            LOG.error("Analytics retention failed; the next scheduled run will retry", failure);
        }
    }
}
