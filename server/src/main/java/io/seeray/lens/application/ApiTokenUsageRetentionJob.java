package io.seeray.lens.application;

import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.sql.Connection;
import java.sql.PreparedStatement;
import javax.sql.DataSource;
import org.jboss.logging.Logger;

/** Keeps request history bounded to the product's published 30-day retention window. */
@ApplicationScoped
public class ApiTokenUsageRetentionJob {
    private static final Logger LOG = Logger.getLogger(ApiTokenUsageRetentionJob.class);
    private final DataSource dataSource;

    @Inject
    public ApiTokenUsageRetentionJob(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Scheduled(every = "24h", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    @Transactional
    public void clean() {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "delete from api_token_request_log where created_at<now()-interval '30 days'")) {
            statement.executeUpdate();
        } catch (Exception error) {
            LOG.warn("Could not clean expired API token request history", error);
        }
    }
}
