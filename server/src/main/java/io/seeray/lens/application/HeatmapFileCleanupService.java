package io.seeray.lens.application;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import javax.sql.DataSource;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/** File deletion is intentionally retried after the DB commit. */
@ApplicationScoped
public class HeatmapFileCleanupService {
    private final DataSource dataSource;
    private final Path storage;

    @Inject
    public HeatmapFileCleanupService(
            DataSource dataSource, @ConfigProperty(name = "seeray.heatmaps.storage-dir") String storage) {
        this.dataSource = dataSource;
        this.storage = Paths.get(storage);
    }

    @Transactional
    public void queue(String key) {
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "insert into heatmap_file_cleanup (file_key) values (?) on conflict do nothing")) {
            s.setString(1, key);
            s.executeUpdate();
        } catch (Exception e) {
            throw new IllegalStateException("Could not queue heatmap file cleanup", e);
        }
    }

    @Transactional
    public void queueSite(UUID site) {
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "insert into heatmap_file_cleanup (file_key) select file_key from heatmap_snapshot where site_id=? on conflict do nothing")) {
            s.setObject(1, site);
            s.executeUpdate();
        } catch (Exception e) {
            throw new IllegalStateException("Could not queue site heatmap cleanup", e);
        }
    }

    @Transactional
    public void process(int limit) {
        List<String> keys = new ArrayList<>();
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "select file_key from heatmap_file_cleanup where next_attempt_at<=now() order by created_at for update skip locked limit ?")) {
            s.setInt(1, limit);
            try (ResultSet rows = s.executeQuery()) {
                while (rows.next()) keys.add(rows.getString(1));
            }
            for (String key : keys) {
                try {
                    deleteFiles(key);
                    try (PreparedStatement done =
                            c.prepareStatement("delete from heatmap_file_cleanup where file_key=?")) {
                        done.setString(1, key);
                        done.executeUpdate();
                    }
                } catch (Exception error) {
                    try (PreparedStatement retry = c.prepareStatement(
                            "update heatmap_file_cleanup set attempts=attempts+1,next_attempt_at=now()+least((attempts+1) * interval '1 minute',interval '1 hour') where file_key=?")) {
                        retry.setString(1, key);
                        retry.executeUpdate();
                    }
                }
            }
        } catch (Exception e) {
            throw new IllegalStateException("Could not clean heatmap files", e);
        }
    }

    private void deleteFiles(String key) throws IOException {
        Files.deleteIfExists(storage.resolve(key));
        Path tiles = storage.resolve(key + ".tiles");
        if (!Files.exists(tiles)) return;
        try (var paths = Files.walk(tiles)) {
            paths.sorted(java.util.Comparator.reverseOrder()).forEach(path -> {
                try {
                    Files.deleteIfExists(path);
                } catch (IOException failure) {
                    throw new UncheckedIOException(failure);
                }
            });
        } catch (UncheckedIOException failure) {
            throw failure.getCause();
        }
    }
}
