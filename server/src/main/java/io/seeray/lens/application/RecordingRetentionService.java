package io.seeray.lens.application;

import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.sql.Connection;
import java.sql.PreparedStatement;
import javax.sql.DataSource;

@ApplicationScoped
public class RecordingRetentionService {
    private final DataSource dataSource;

    public RecordingRetentionService(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Scheduled(every = "1h", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    @Transactional
    void deleteExpired() {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement =
                        connection.prepareStatement("delete from session_recording where expires_at < now()")) {
            statement.executeUpdate();
        } catch (Exception error) {
            throw new IllegalStateException("Could not delete expired session recordings", error);
        }
    }
}
