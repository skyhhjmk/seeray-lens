package io.seeray.lens.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;
import javax.sql.DataSource;

@ApplicationScoped
public class RecordingCaptureService {
    public static final int PROTOCOL_VERSION = 1;
    private static final int SNAPSHOT_LIMIT = 2 * 1024 * 1024;
    private static final int CHUNK_LIMIT = 256 * 1024;
    private static final long RECORDING_LIMIT = 20L * 1024 * 1024;

    private final DataSource dataSource;
    private final ObjectMapper mapper;
    private final HeatmapVariantService variants;
    private final SiteService sites;
    private final WorkspaceAccess access;

    public RecordingCaptureService(
            DataSource dataSource,
            ObjectMapper mapper,
            HeatmapVariantService variants,
            SiteService sites,
            WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.mapper = mapper;
        this.variants = variants;
        this.sites = sites;
        this.access = access;
    }

    @Transactional
    public DomSnapshot captureSnapshot(Site site, SnapshotUpload request) {
        validateProtocol(request.protocolVersion());
        int bytes = size(request.events(), SNAPSHOT_LIMIT, "DOM_SNAPSHOT_TOO_LARGE");
        String pageUrl = cleanUrl(request.url());
        try (Connection connection = dataSource.getConnection()) {
            UUID variantId = variants.resolve(
                    connection,
                    site.id,
                    new HeatmapVariantService.Identity(
                            pageUrl,
                            request.layoutVersion(),
                            request.targetId(),
                            request.viewportWidth(),
                            request.viewportHeight(),
                            request.contentWidth(),
                            request.contentHeight()));
            UUID id = UuidV7.next();
            Instant now = Instant.now();
            try (PreparedStatement statement = connection.prepareStatement(
                    "insert into heatmap_dom_snapshot (id,site_id,variant_id,source_instance_id,protocol_version,payload,payload_bytes,created_at) values (?,?,?,?,?,?::jsonb,?,?) on conflict (variant_id) do nothing")) {
                statement.setObject(1, id);
                statement.setObject(2, site.id);
                statement.setObject(3, variantId);
                statement.setObject(4, request.instanceId());
                statement.setInt(5, request.protocolVersion());
                statement.setString(6, mapper.writeValueAsString(request.events()));
                statement.setInt(7, bytes);
                statement.setTimestamp(8, Timestamp.from(now));
                if (statement.executeUpdate() == 1)
                    return new DomSnapshot(id, variantId, request.protocolVersion(), bytes, now, true);
            }
            try (PreparedStatement statement = connection.prepareStatement(
                    "select id,protocol_version,payload_bytes,created_at from heatmap_dom_snapshot where variant_id=?")) {
                statement.setObject(1, variantId);
                try (ResultSet row = statement.executeQuery()) {
                    if (!row.next()) throw new SQLException("Could not resolve DOM snapshot");
                    return new DomSnapshot(
                            row.getObject(1, UUID.class),
                            variantId,
                            row.getInt(2),
                            row.getInt(3),
                            row.getTimestamp(4).toInstant(),
                            false);
                }
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new IllegalStateException("Could not store DOM snapshot", error);
        }
    }

    public SnapshotPlan planSnapshot(Site site, SnapshotIdentity request) {
        String pageUrl = cleanUrl(request.url());
        try (Connection connection = dataSource.getConnection()) {
            UUID variantId = variants.resolve(
                    connection,
                    site.id,
                    new HeatmapVariantService.Identity(
                            pageUrl,
                            request.layoutVersion(),
                            request.targetId(),
                            request.viewportWidth(),
                            request.viewportHeight(),
                            request.contentWidth(),
                            request.contentHeight()));
            try (PreparedStatement statement = connection.prepareStatement(
                    "select exists(select 1 from heatmap_dom_snapshot where variant_id=?)")) {
                statement.setObject(1, variantId);
                try (ResultSet row = statement.executeQuery()) {
                    row.next();
                    return new SnapshotPlan(variantId, !row.getBoolean(1));
                }
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new IllegalStateException("Could not plan DOM snapshot", error);
        }
    }

    @Transactional
    public RecordingResult captureRecording(Site site, int retentionDays, RecordingUpload request) {
        validateProtocol(request.protocolVersion());
        int bytes = size(request.events(), CHUNK_LIMIT, "RECORDING_CHUNK_TOO_LARGE");
        if (request.sequence() < 0 || request.startedOffsetMs() < 0)
            throw new ControlPlaneException(400, "INVALID_RECORDING_CHUNK", "Recording chunk is invalid");
        String pageUrl = cleanUrl(request.url());
        try (Connection connection = dataSource.getConnection()) {
            RecordingState state =
                    lockRecording(connection, site.id, retentionDays, request.recordingId(), request.sequence() == 0);
            if (state.truncated()) return new RecordingResult(request.recordingId(), request.sequence(), false, true);
            try (PreparedStatement duplicate = connection.prepareStatement(
                    "select 1 from session_recording_chunk where recording_id=? and page_instance_id=? and sequence=?")) {
                duplicate.setObject(1, request.recordingId());
                duplicate.setObject(2, request.instanceId());
                duplicate.setInt(3, request.sequence());
                try (ResultSet rows = duplicate.executeQuery()) {
                    if (rows.next())
                        return new RecordingResult(request.recordingId(), request.sequence(), false, false);
                }
            }
            if (state.bytes() + bytes > RECORDING_LIMIT) {
                try (PreparedStatement statement = connection.prepareStatement(
                        "update session_recording set truncated=true,ended_at=coalesce(ended_at,now()) where id=?")) {
                    statement.setObject(1, request.recordingId());
                    statement.executeUpdate();
                }
                return new RecordingResult(request.recordingId(), request.sequence(), false, true);
            }
            try (PreparedStatement statement = connection.prepareStatement(
                    "insert into session_recording_chunk (recording_id,sequence,page_instance_id,page_url,protocol_version,payload,payload_bytes,event_count,started_offset_ms) values (?,?,?,?,?,?::jsonb,?,?,?)")) {
                statement.setObject(1, request.recordingId());
                statement.setInt(2, request.sequence());
                statement.setObject(3, request.instanceId());
                statement.setString(4, pageUrl);
                statement.setInt(5, request.protocolVersion());
                statement.setString(6, mapper.writeValueAsString(request.events()));
                statement.setInt(7, bytes);
                statement.setInt(8, request.events().size());
                statement.setInt(9, request.startedOffsetMs());
                statement.executeUpdate();
            }
            try (PreparedStatement statement = connection.prepareStatement(
                    "update session_recording set byte_count=byte_count+?,event_count=event_count+?,page_count=(select count(distinct page_instance_id) from session_recording_chunk where recording_id=?),ended_at=case when ? then now() else null end where id=?")) {
                statement.setInt(1, bytes);
                statement.setInt(2, request.events().size());
                statement.setObject(3, request.recordingId());
                statement.setBoolean(4, request.finalChunk());
                statement.setObject(5, request.recordingId());
                statement.executeUpdate();
            }
            return new RecordingResult(request.recordingId(), request.sequence(), true, false);
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new IllegalStateException("Could not store session recording", error);
        }
    }

    public List<RecordingSummary> recordings(UUID siteId, int limit) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select id,started_at,ended_at,page_count,event_count,byte_count,truncated from session_recording where site_id=? order by started_at desc limit ?")) {
            statement.setObject(1, siteId);
            statement.setInt(2, Math.max(1, Math.min(limit, 200)));
            List<RecordingSummary> output = new ArrayList<>();
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next())
                    output.add(new RecordingSummary(
                            rows.getObject(1, UUID.class),
                            rows.getTimestamp(2).toInstant(),
                            rows.getTimestamp(3) == null
                                    ? null
                                    : rows.getTimestamp(3).toInstant(),
                            rows.getInt(4),
                            rows.getInt(5),
                            rows.getLong(6),
                            rows.getBoolean(7)));
            }
            return output;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list session recordings", error);
        }
    }

    public List<RecordingChunk> recording(UUID siteId, UUID recordingId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select c.sequence,c.page_instance_id,c.page_url,c.protocol_version,c.payload,c.started_offset_ms from session_recording_chunk c join session_recording r on r.id=c.recording_id where r.site_id=? and r.id=? order by c.received_at,c.sequence")) {
            statement.setObject(1, siteId);
            statement.setObject(2, recordingId);
            List<RecordingChunk> output = new ArrayList<>();
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next())
                    output.add(new RecordingChunk(
                            rows.getInt(1),
                            rows.getObject(2, UUID.class),
                            rows.getString(3),
                            rows.getInt(4),
                            mapper.readTree(rows.getString(5)),
                            rows.getInt(6)));
            }
            if (output.isEmpty()) throw new ControlPlaneException(404, "RECORDING_NOT_FOUND", "Recording not found");
            return output;
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new IllegalStateException("Could not read session recording", error);
        }
    }

    public JsonNode snapshot(UUID siteId, UUID variantId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select payload from heatmap_dom_snapshot where site_id=? and variant_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, variantId);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next())
                    throw new ControlPlaneException(404, "DOM_SNAPSHOT_NOT_FOUND", "DOM snapshot not found");
                return mapper.readTree(rows.getString(1));
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new IllegalStateException("Could not read DOM snapshot", error);
        }
    }

    public DomSnapshot snapshotMetadata(UUID siteId, UUID variantId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select id,protocol_version,payload_bytes,created_at from heatmap_dom_snapshot where site_id=? and variant_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, variantId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next())
                    throw new ControlPlaneException(404, "DOM_SNAPSHOT_NOT_FOUND", "DOM snapshot not found");
                return new DomSnapshot(
                        row.getObject(1, UUID.class),
                        variantId,
                        row.getInt(2),
                        row.getInt(3),
                        row.getTimestamp(4).toInstant(),
                        false);
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new IllegalStateException("Could not read DOM snapshot metadata", error);
        }
    }

    private RecordingState lockRecording(
            Connection connection, UUID siteId, int retentionDays, UUID recordingId, boolean mayCreate)
            throws SQLException {
        if (mayCreate) {
            try (PreparedStatement insert = connection.prepareStatement(
                    "insert into session_recording (id,site_id,started_at,expires_at) values (?,?,now(),?) on conflict do nothing")) {
                insert.setObject(1, recordingId);
                insert.setObject(2, siteId);
                insert.setTimestamp(3, Timestamp.from(Instant.now().plus(retentionDays, ChronoUnit.DAYS)));
                insert.executeUpdate();
            }
        }
        try (PreparedStatement statement = connection.prepareStatement(
                "select site_id,byte_count,truncated from session_recording where id=? for update")) {
            statement.setObject(1, recordingId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next() || !siteId.equals(row.getObject(1, UUID.class)))
                    throw new ControlPlaneException(400, "INVALID_RECORDING", "Recording does not belong to site");
                return new RecordingState(row.getLong(2), row.getBoolean(3));
            }
        }
    }

    private int size(JsonNode payload, int limit, String code) {
        try {
            int bytes = mapper.writeValueAsBytes(payload).length;
            if (!payload.isArray() || payload.isEmpty())
                throw new ControlPlaneException(400, "INVALID_RECORDING_PAYLOAD", "Recording payload must be an array");
            if (bytes > limit) throw new ControlPlaneException(413, code, "Capture payload is too large");
            return bytes;
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new ControlPlaneException(400, "INVALID_RECORDING_PAYLOAD", "Recording payload is invalid");
        }
    }

    private static void validateProtocol(int protocol) {
        if (protocol != PROTOCOL_VERSION)
            throw new ControlPlaneException(
                    400, "UNSUPPORTED_RECORDING_PROTOCOL", "Recording protocol is not supported");
    }

    private String cleanUrl(String value) {
        TrackingSanitizer.CleanUrl clean = TrackingSanitizer.url(value, mapper);
        if (clean == null) throw new ControlPlaneException(400, "INVALID_RECORDING_URL", "Recording URL is invalid");
        return clean.scheme() + "://" + clean.host() + clean.path();
    }

    private record RecordingState(long bytes, boolean truncated) {}

    public record SnapshotUpload(
            int protocolVersion,
            UUID instanceId,
            String url,
            String layoutVersion,
            String targetId,
            int viewportWidth,
            int viewportHeight,
            int contentWidth,
            int contentHeight,
            JsonNode events) {}

    public record SnapshotIdentity(
            String url,
            String layoutVersion,
            String targetId,
            int viewportWidth,
            int viewportHeight,
            int contentWidth,
            int contentHeight) {}

    public record SnapshotPlan(UUID variantId, boolean captureRequired) {}

    public record RecordingUpload(
            int protocolVersion,
            UUID recordingId,
            UUID instanceId,
            int sequence,
            int startedOffsetMs,
            boolean finalChunk,
            String url,
            JsonNode events) {}

    public record DomSnapshot(
            UUID id, UUID variantId, int protocolVersion, int payloadBytes, Instant createdAt, boolean captured) {}

    public record RecordingResult(UUID recordingId, int sequence, boolean accepted, boolean truncated) {}

    public record RecordingSummary(
            UUID id,
            Instant startedAt,
            Instant endedAt,
            int pageCount,
            int eventCount,
            long byteCount,
            boolean truncated) {}

    public record RecordingChunk(
            int sequence,
            UUID pageInstanceId,
            String pageUrl,
            int protocolVersion,
            JsonNode events,
            int startedOffsetMs) {}
}
