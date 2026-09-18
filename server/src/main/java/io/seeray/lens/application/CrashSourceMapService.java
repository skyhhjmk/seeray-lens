package io.seeray.lens.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.sql.DataSource;

/** Owner/admin-managed maps used only to translate anonymous JavaScript error positions. */
@ApplicationScoped
public class CrashSourceMapService {
    private final DataSource dataSource;
    private final ObjectMapper mapper;
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final Map<String, SourceMapV3> decoderCache = new LinkedHashMap<>(4, .75f, true) {
        @Override
        protected boolean removeEldestEntry(Map.Entry<String, SourceMapV3> eldest) {
            return size() > 2;
        }
    };

    @Inject
    public CrashSourceMapService(
            DataSource dataSource, ObjectMapper mapper, SiteService sites, WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.mapper = mapper;
        this.sites = sites;
        this.access = access;
    }

    public SourceMapListDto list(UUID siteId) {
        Site site = sites.site(siteId);
        var member = access.member(site.organization.id);
        List<SourceMapDto> maps = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        """
                        select id, release_id, bundle_path, source_count, updated_at
                        from crash_source_map where site_id=? order by updated_at desc, release_id, bundle_path
                        """)) {
            statement.setObject(1, siteId);
            try (ResultSet result = statement.executeQuery()) {
                while (result.next())
                    maps.add(new SourceMapDto(
                            result.getObject(1, UUID.class),
                            result.getString(2),
                            result.getString(3),
                            result.getInt(4),
                            result.getTimestamp(5).toInstant()));
            }
            boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
            return new SourceMapListDto(canManage, List.copyOf(maps));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list crash source maps", error);
        }
    }

    public SourceMapDto upload(UUID siteId, String releaseId, String bundlePath, JsonNode sourceMap) {
        authorize(siteId, true);
        String release = validateRelease(releaseId);
        String path = normalizeBundlePath(bundlePath);
        SourceMapV3.Prepared prepared = SourceMapV3.prepare(sourceMap, mapper);
        String json;
        try {
            json = mapper.writeValueAsString(prepared.json());
        } catch (Exception error) {
            throw new IllegalStateException("Could not store crash source map", error);
        }
        UUID id = UuidV7.next();
        Instant updatedAt;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        """
                insert into crash_source_map(id,site_id,release_id,bundle_path,source_count,map_json,created_at,updated_at)
                values (?,?,?,?,?,?::jsonb,now(),now())
                on conflict (site_id,release_id,bundle_path) do update set
                  source_count=excluded.source_count,map_json=excluded.map_json,updated_at=now()
                returning id,updated_at
                """)) {
            statement.setObject(1, id);
            statement.setObject(2, siteId);
            statement.setString(3, release);
            statement.setString(4, path);
            statement.setInt(5, prepared.sourceCount());
            statement.setString(6, json);
            try (ResultSet result = statement.executeQuery()) {
                result.next();
                id = result.getObject(1, UUID.class);
                updatedAt = result.getTimestamp(2).toInstant();
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save crash source map", error);
        }
        evict(id);
        return new SourceMapDto(id, release, path, prepared.sourceCount(), updatedAt);
    }

    public void delete(UUID siteId, UUID mapId) {
        authorize(siteId, true);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement =
                        connection.prepareStatement("delete from crash_source_map where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, mapId);
            if (statement.executeUpdate() == 0)
                throw new ControlPlaneException(404, "SOURCE_MAP_NOT_FOUND", "Source map not found");
            evict(mapId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not delete crash source map", error);
        }
    }

    /** Returns a mapped, path-scrubbed position or leaves the already sanitized location unchanged. */
    public boolean symbolicate(UUID siteId, java.util.Map<String, Object> cleanCrashData) {
        Object rawRelease = cleanCrashData.get("releaseId");
        Object rawPath = cleanCrashData.get("sourcePath");
        Object rawLine = cleanCrashData.get("line");
        Object rawColumn = cleanCrashData.get("column");
        if (!(rawRelease instanceof String release)
                || !(rawPath instanceof String path)
                || !(rawLine instanceof Integer line)
                || !(rawColumn instanceof Integer column)) return false;
        if (!release.matches("[A-Za-z0-9][A-Za-z0-9._+-]{0,99}")) return false;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        """
                select id, map_json::text, updated_at from crash_source_map where site_id=? and release_id=? and bundle_path=?
                """)) {
            statement.setObject(1, siteId);
            statement.setString(2, release);
            statement.setString(3, TrackingSanitizer.safeCrashPath(path));
            try (ResultSet result = statement.executeQuery()) {
                if (!result.next()) return false;
                UUID mapId = result.getObject(1, UUID.class);
                String cacheKey = mapId + ":" + result.getTimestamp(3).toInstant();
                SourceMapV3 decoder = decoderCache(cacheKey);
                if (decoder == null) {
                    JsonNode json = mapper.readTree(result.getString(2));
                    decoder = SourceMapV3.prepare(json, mapper).decoder();
                    cache(cacheKey, decoder);
                }
                SourceMapV3.Mapping position = decoder.originalPosition(line, column - 1);
                if (position == null) return false;
                cleanCrashData.put("sourcePath", position.source());
                cleanCrashData.put("line", position.line());
                cleanCrashData.put("column", position.column() + 1);
                String functionName = CrashDataSanitizer.safeFunctionName(position.name());
                if (functionName != null) cleanCrashData.put("functionName", functionName);
                CrashDataSanitizer.refreshFingerprint(cleanCrashData);
                return true;
            }
        } catch (Exception ignored) {
            // Bad, stale, or incompatible maps never reject anonymous collection.
            return false;
        }
    }

    private void authorize(UUID siteId, boolean write) {
        Site site = sites.site(siteId);
        if (write) access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
    }

    private SourceMapV3 decoderCache(String key) {
        synchronized (decoderCache) {
            return decoderCache.get(key);
        }
    }

    private void cache(String key, SourceMapV3 decoder) {
        synchronized (decoderCache) {
            decoderCache.put(key, decoder);
        }
    }

    private void evict(UUID mapId) {
        synchronized (decoderCache) {
            decoderCache.keySet().removeIf(key -> key.startsWith(mapId + ":"));
        }
    }

    private static String validateRelease(String value) {
        String release = value == null ? "" : value.strip();
        if (!release.matches("[A-Za-z0-9][A-Za-z0-9._+-]{0,99}"))
            throw new ControlPlaneException(
                    400,
                    "INVALID_RELEASE",
                    "Release must be 1-100 letters, digits, dot, underscore, plus, or hyphen characters");
        return release;
    }

    private static String normalizeBundlePath(String value) {
        String path = value == null ? "" : value.strip();
        if (path.isBlank() || path.length() > 2048)
            throw new ControlPlaneException(400, "INVALID_BUNDLE_PATH", "A JavaScript bundle path is required");
        String safe = TrackingSanitizer.safeCrashPath(path);
        if (safe.equals("/"))
            throw new ControlPlaneException(400, "INVALID_BUNDLE_PATH", "A JavaScript bundle path is required");
        return safe;
    }

    public record SourceMapListDto(boolean canManage, List<SourceMapDto> maps) {}

    public record SourceMapDto(UUID id, String releaseId, String bundlePath, int sourceCount, Instant updatedAt) {}
}
