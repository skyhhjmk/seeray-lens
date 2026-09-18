package io.seeray.lens.application;

import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import java.sql.Connection;
import java.sql.PreparedStatement;
import javax.sql.DataSource;
import org.jboss.logging.Logger;

@ApplicationScoped
public class WorkspaceWriteAccessRetentionJob {
    private static final Logger LOG = Logger.getLogger(WorkspaceWriteAccessRetentionJob.class);
    private final DataSource dataSource;

    public WorkspaceWriteAccessRetentionJob(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Scheduled(every = "24h", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    public void clean() {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "delete from workspace_api_write_log where created_at<now()-interval '30 days'")) {
            statement.executeUpdate();
        } catch (Exception error) {
            LOG.warn("Could not clean expired workspace API write history", error);
        }
    }
}
