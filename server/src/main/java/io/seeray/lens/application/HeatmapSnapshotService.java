package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.awt.image.BufferedImage;
import java.io.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import javax.sql.DataSource;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
public class HeatmapSnapshotService {
    public static final int TILE_HEIGHT = 2048;
    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final HeatmapFileCleanupService cleanup;
    private final Path storage;

    @Inject
    public HeatmapSnapshotService(
            DataSource dataSource,
            SiteService sites,
            WorkspaceAccess access,
            HeatmapFileCleanupService cleanup,
            @ConfigProperty(name = "seeray.heatmaps.storage-dir") String storage) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
        this.cleanup = cleanup;
        this.storage = Paths.get(storage);
    }

    public List<Snapshot> list(UUID siteId, UUID variantId) {
        site(siteId);
        String sql =
                "select id,variant_id,file_key,content_type,image_width,image_height,image_hash,created_at from heatmap_snapshot where site_id=?"
                        + (variantId == null ? "" : " and variant_id=?") + " order by created_at desc";
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(sql)) {
            s.setObject(1, siteId);
            if (variantId != null) s.setObject(2, variantId);
            List<Snapshot> out = new ArrayList<>();
            try (ResultSet rows = s.executeQuery()) {
                while (rows.next()) out.add(row(rows));
            }
            return out;
        } catch (SQLException e) {
            throw new IllegalStateException("Could not read heatmap snapshots", e);
        }
    }

    @Transactional
    public Snapshot upload(UUID siteId, UUID variantId, InputStream input, String mediaType) {
        Site site = admin(siteId);
        Variant variant = variant(siteId, variantId);
        if (!"image/png".equals(mediaType) && !"image/jpeg".equals(mediaType))
            throw new ControlPlaneException(415, "UNSUPPORTED_SNAPSHOT", "Only PNG and JPEG snapshots are supported");
        try {
            byte[] bytes = input.readNBytes(20 * 1024 * 1024 + 1);
            if (bytes.length > 20 * 1024 * 1024)
                throw new ControlPlaneException(413, "SNAPSHOT_TOO_LARGE", "Snapshot must be 20 MiB or smaller");
            BufferedImage image = decodeSupportedImage(bytes);
            if (image == null
                    || image.getWidth() > 32768
                    || image.getHeight() > 32768
                    || (long) image.getWidth() * image.getHeight() > 40_000_000L)
                throw new ControlPlaneException(400, "INVALID_SNAPSHOT", "Snapshot dimensions are not supported");
            double expected = (double) variant.width / variant.height,
                    actual = (double) image.getWidth() / image.getHeight();
            if (Math.abs(expected - actual) / expected > 0.01)
                throw new ControlPlaneException(
                        400,
                        "SNAPSHOT_DIMENSIONS_MISMATCH",
                        "Snapshot aspect ratio does not match the heatmap variant");
            String key = UuidV7.next() + ".png";
            Files.createDirectories(storage);
            Path file = storage.resolve(key);
            ImageIO.write(image, "png", file.toFile());
            writeTiles(image, key);
            Snapshot snapshot = new Snapshot(
                    UuidV7.next(),
                    variantId,
                    key,
                    "image/png",
                    image.getWidth(),
                    image.getHeight(),
                    hash(Files.readAllBytes(file)),
                    Instant.now());
            try {
                try (Connection c = dataSource.getConnection();
                        PreparedStatement s = c.prepareStatement(
                                "insert into heatmap_snapshot (id,site_id,variant_id,file_key,content_type,image_width,image_height,image_hash,uploaded_by,created_at) values (?,?,?,?,?,?,?,?,?,?)")) {
                    s.setObject(1, snapshot.id);
                    s.setObject(2, siteId);
                    s.setObject(3, variantId);
                    s.setString(4, key);
                    s.setString(5, snapshot.contentType);
                    s.setInt(6, snapshot.width);
                    s.setInt(7, snapshot.height);
                    s.setString(8, snapshot.hash);
                    s.setObject(9, access.userId());
                    s.setObject(10, snapshot.createdAt);
                    s.executeUpdate();
                }
            } catch (Exception metadataFailure) {
                try {
                    deleteFiles(key);
                } catch (IOException ignored) {
                    cleanup.queue(key);
                }
                throw metadataFailure;
            }
            return snapshot;
        } catch (ControlPlaneException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalStateException("Could not store heatmap snapshot", e);
        }
    }

    public FileData image(UUID siteId, UUID snapshotId) {
        site(siteId);
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "select file_key,content_type from heatmap_snapshot where id=? and site_id=?")) {
            s.setObject(1, snapshotId);
            s.setObject(2, siteId);
            try (ResultSet r = s.executeQuery()) {
                if (!r.next()) throw new ControlPlaneException(404, "SNAPSHOT_NOT_FOUND", "Heatmap snapshot not found");
                Path file = storage.resolve(r.getString(1));
                if (!Files.isRegularFile(file))
                    throw new ControlPlaneException(404, "SNAPSHOT_FILE_NOT_FOUND", "Heatmap snapshot file not found");
                return new FileData(file, r.getString(2));
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not read heatmap snapshot", e);
        }
    }

    public FileData tile(UUID siteId, UUID snapshotId, int tile) {
        site(siteId);
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "select file_key,image_height from heatmap_snapshot where id=? and site_id=?")) {
            s.setObject(1, snapshotId);
            s.setObject(2, siteId);
            try (ResultSet r = s.executeQuery()) {
                if (!r.next()) throw new ControlPlaneException(404, "SNAPSHOT_NOT_FOUND", "Heatmap snapshot not found");
                int count = tileCount(r.getInt(2));
                if (tile < 0 || tile >= count)
                    throw new ControlPlaneException(404, "SNAPSHOT_TILE_NOT_FOUND", "Heatmap snapshot tile not found");
                Path file = tilePath(r.getString(1), tile);
                if (!Files.isRegularFile(file))
                    throw new ControlPlaneException(404, "SNAPSHOT_TILE_NOT_FOUND", "Heatmap snapshot tile not found");
                return new FileData(file, "image/png");
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not read heatmap snapshot tile", e);
        }
    }

    @Transactional
    public void delete(UUID siteId, UUID snapshotId) {
        admin(siteId);
        String key;
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "delete from heatmap_snapshot where id=? and site_id=? returning file_key")) {
            s.setObject(1, snapshotId);
            s.setObject(2, siteId);
            try (ResultSet r = s.executeQuery()) {
                if (!r.next()) throw new ControlPlaneException(404, "SNAPSHOT_NOT_FOUND", "Heatmap snapshot not found");
                key = r.getString(1);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not delete heatmap snapshot", e);
        }
        cleanup.queue(key);
    }

    private Site site(UUID id) {
        Site site = sites.site(id);
        access.member(site.organization.id);
        return site;
    }

    private Site admin(UUID id) {
        Site site = sites.site(id);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return site;
    }

    private Variant variant(UUID site, UUID id) {
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "select content_width,content_height from heatmap_variant where id=? and site_id=?")) {
            s.setObject(1, id);
            s.setObject(2, site);
            try (ResultSet r = s.executeQuery()) {
                if (!r.next())
                    throw new ControlPlaneException(404, "HEATMAP_VARIANT_NOT_FOUND", "Heatmap variant not found");
                return new Variant(r.getInt(1), r.getInt(2));
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not read heatmap variant", e);
        }
    }

    private static Snapshot row(ResultSet r) throws SQLException {
        return new Snapshot(
                r.getObject(1, UUID.class),
                r.getObject(2, UUID.class),
                r.getString(3),
                r.getString(4),
                r.getInt(5),
                r.getInt(6),
                r.getString(7),
                r.getTimestamp(8).toInstant());
    }

    private void writeTiles(BufferedImage image, String key) throws IOException {
        Path directory = storage.resolve(key + ".tiles");
        Files.createDirectories(directory);
        for (int top = 0, tile = 0; top < image.getHeight(); top += TILE_HEIGHT, tile++) {
            int height = Math.min(TILE_HEIGHT, image.getHeight() - top);
            ImageIO.write(
                    image.getSubimage(0, top, image.getWidth(), height),
                    "png",
                    tilePath(key, tile).toFile());
        }
    }

    /** Uses the bytes, rather than the HTTP header or filename, as the image type authority. */
    static BufferedImage decodeSupportedImage(byte[] bytes) throws IOException {
        try (ImageInputStream input = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext())
                throw new ControlPlaneException(400, "INVALID_SNAPSHOT", "Snapshot is not a readable image");
            ImageReader reader = readers.next();
            try {
                String format = reader.getFormatName().toLowerCase(Locale.ROOT);
                if (!format.equals("png") && !format.equals("jpeg"))
                    throw new ControlPlaneException(
                            415, "UNSUPPORTED_SNAPSHOT", "Only PNG and JPEG snapshots are supported");
                reader.setInput(input, true, true);
                BufferedImage image = reader.read(0);
                if (image == null)
                    throw new ControlPlaneException(400, "INVALID_SNAPSHOT", "Snapshot is not a readable image");
                return image;
            } finally {
                reader.dispose();
            }
        }
    }

    private void deleteFiles(String key) throws IOException {
        Files.deleteIfExists(storage.resolve(key));
        Path tiles = storage.resolve(key + ".tiles");
        if (Files.exists(tiles)) {
            try (var paths = Files.walk(tiles)) {
                paths.sorted(Comparator.reverseOrder()).forEach(path -> {
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

    private Path tilePath(String key, int tile) {
        return storage.resolve(key + ".tiles").resolve(tile + ".png");
    }

    public static int tileCount(int imageHeight) {
        return Math.max(1, (imageHeight + TILE_HEIGHT - 1) / TILE_HEIGHT);
    }

    private static String hash(byte[] bytes) throws Exception {
        StringBuilder value = new StringBuilder();
        for (byte b : MessageDigest.getInstance("SHA-256").digest(bytes)) value.append(String.format("%02x", b));
        return value.toString();
    }

    private record Variant(int width, int height) {}

    public record Snapshot(
            UUID id,
            UUID variantId,
            String fileKey,
            String contentType,
            int width,
            int height,
            String hash,
            Instant createdAt) {
        public int tileCount() {
            return HeatmapSnapshotService.tileCount(height);
        }
    }

    public record FileData(Path file, String contentType) {}
}
