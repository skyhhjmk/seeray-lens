package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.*;
import java.util.*;
import javax.sql.DataSource;

@ApplicationScoped
public class HeatmapQueryService {
    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;

    @Inject
    public HeatmapQueryService(DataSource dataSource, SiteService sites, WorkspaceAccess access) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
    }

    public List<Variant> variants(UUID siteId, String page) {
        Site site = site(siteId);
        String sql =
                "select v.id,v.page_url,v.layout_version,v.target_id,v.viewport_width,v.viewport_height,v.content_width,v.content_height,v.created_at"
                        + " from heatmap_variant v left join heatmap_instance_fact i on i.variant_id=v.id and i.site_id=v.site_id"
                        + " where v.site_id=?"
                        + (page == null || page.isBlank() ? "" : " and v.page_url=?")
                        + " group by v.id,v.page_url,v.layout_version,v.target_id,v.viewport_width,v.viewport_height,v.content_width,v.content_height,v.created_at"
                        + " order by count(i.page_instance_id) desc,v.created_at desc limit 500";
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(sql)) {
            s.setObject(1, siteId);
            if (page != null && !page.isBlank()) s.setString(2, page);
            List<Variant> result = new ArrayList<>();
            try (ResultSet r = s.executeQuery()) {
                while (r.next())
                    result.add(new Variant(
                            r.getObject(1, UUID.class),
                            r.getString(2),
                            r.getString(3),
                            r.getString(4),
                            r.getInt(5),
                            r.getInt(6),
                            r.getInt(7),
                            r.getInt(8),
                            r.getTimestamp(9).toInstant()));
            }
            return result;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query heatmap variants", error);
        }
    }

    public List<Page> pages(UUID siteId, int offset, int limit) {
        site(siteId);
        int safeOffset = Math.max(0, offset), safeLimit = Math.max(1, Math.min(100, limit));
        String sql = "select v.page_url,count(distinct i.page_instance_id) from heatmap_variant v"
                + " left join heatmap_instance_fact i on i.variant_id=v.id and i.site_id=v.site_id"
                + " where v.site_id=? group by v.page_url order by count(distinct i.page_instance_id) desc,v.page_url asc offset ? limit ?";
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(sql)) {
            s.setObject(1, siteId);
            s.setInt(2, safeOffset);
            s.setInt(3, safeLimit);
            List<Page> result = new ArrayList<>();
            try (ResultSet r = s.executeQuery()) {
                while (r.next()) result.add(new Page(r.getString(1), r.getLong(2)));
            }
            return result;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query heatmap pages", error);
        }
    }

    public Stats stats(UUID siteId, UUID variant, String from, String to, String type) {
        site(siteId);
        if (!Set.of("click", "move", "scroll").contains(type))
            throw new ControlPlaneException(400, "INVALID_HEATMAP_TYPE", "Heatmap type must be click, move, or scroll");
        AnalyticsQueryService.Range range =
                new AnalyticsQueryService(dataSource, sites, access).range(siteId, from, to);
        Variant v = variant(siteId, variant);
        if (type.equals("scroll")) return scroll(siteId, variant, range, v);
        return grid(siteId, variant, range, type, v);
    }

    private Stats grid(UUID site, UUID variant, AnalyticsQueryService.Range range, String type, Variant v) {
        List<Cell> cells = new ArrayList<>();
        long total = 0;
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "select grid_x,grid_y,sum(event_count) from heatmap_grid_daily where site_id=? and variant_id=? and event_type=? and business_date between ? and ? group by grid_x,grid_y order by grid_y,grid_x")) {
            s.setObject(1, site);
            s.setObject(2, variant);
            s.setString(3, type);
            s.setObject(4, range.from());
            s.setObject(5, range.to());
            try (ResultSet r = s.executeQuery()) {
                while (r.next()) {
                    Cell cell = new Cell(r.getInt(1), r.getInt(2), r.getLong(3));
                    cells.add(cell);
                    total += cell.count;
                }
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query heatmap grid", e);
        }
        int gridSize = 16;
        while (cells.size() > 100_000) {
            gridSize *= 2;
            Map<String, Long> merged = new LinkedHashMap<>();
            int divisor = gridSize / 16;
            for (Cell cell : cells) merged.merge((cell.x / divisor) + ":" + (cell.y / divisor), cell.count, Long::sum);
            cells = new ArrayList<>();
            for (Map.Entry<String, Long> entry : merged.entrySet()) {
                String[] point = entry.getKey().split(":", 2);
                cells.add(new Cell(Integer.parseInt(point[0]), Integer.parseInt(point[1]), entry.getValue()));
            }
        }
        long instances = instances(site, variant, range);
        Sampling sampling = sampling(site, variant, range);
        Quality quality = quality(site, variant, range);
        return new Stats(
                v,
                type,
                gridSize,
                instances,
                total,
                sampling.minimum,
                sampling.maximum,
                quality.truncatedInstances,
                quality.dropped,
                List.copyOf(cells),
                List.of(),
                Instant.now());
    }

    private Stats scroll(UUID site, UUID variant, AnalyticsQueryService.Range range, Variant v) {
        List<Depth> depth = new ArrayList<>();
        long total = 0;
        long instanceCount = instances(site, variant, range);
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "select depth_bin,sum(reached_count) from heatmap_scroll_daily where site_id=? and variant_id=? and business_date between ? and ? group by depth_bin order by depth_bin")) {
            s.setObject(1, site);
            s.setObject(2, variant);
            s.setObject(3, range.from());
            s.setObject(4, range.to());
            try (ResultSet r = s.executeQuery()) {
                while (r.next()) {
                    long reached = r.getLong(2);
                    depth.add(new Depth(
                            r.getInt(1),
                            reached,
                            instanceCount,
                            instanceCount == 0 ? 0 : (double) reached / instanceCount));
                    total += reached;
                }
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query heatmap scroll", e);
        }
        Sampling sampling = sampling(site, variant, range);
        Quality quality = quality(site, variant, range);
        return new Stats(
                v,
                "scroll",
                16,
                instanceCount,
                total,
                sampling.minimum,
                sampling.maximum,
                quality.truncatedInstances,
                quality.dropped,
                List.of(),
                List.copyOf(depth),
                Instant.now());
    }

    private long instances(UUID site, UUID variant, AnalyticsQueryService.Range range) {
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "select count(*) from heatmap_instance_fact where site_id=? and variant_id=? and business_date between ? and ?")) {
            s.setObject(1, site);
            s.setObject(2, variant);
            s.setObject(3, range.from());
            s.setObject(4, range.to());
            try (ResultSet r = s.executeQuery()) {
                r.next();
                return r.getLong(1);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query heatmap instances", e);
        }
    }

    private Sampling sampling(UUID site, UUID variant, AnalyticsQueryService.Range range) {
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "select coalesce(min(sample_rate),0),coalesce(max(sample_rate),0) from heatmap_instance_fact where site_id=? and variant_id=? and business_date between ? and ?")) {
            s.setObject(1, site);
            s.setObject(2, variant);
            s.setObject(3, range.from());
            s.setObject(4, range.to());
            try (ResultSet r = s.executeQuery()) {
                r.next();
                return new Sampling(r.getInt(1), r.getInt(2));
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query heatmap sampling", e);
        }
    }

    private Quality quality(UUID site, UUID variant, AnalyticsQueryService.Range range) {
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(
                        "select count(*) filter (where truncated),coalesce(sum(dropped_count),0) from heatmap_instance_fact where site_id=? and variant_id=? and business_date between ? and ?")) {
            s.setObject(1, site);
            s.setObject(2, variant);
            s.setObject(3, range.from());
            s.setObject(4, range.to());
            try (ResultSet r = s.executeQuery()) {
                r.next();
                return new Quality(r.getLong(1), r.getLong(2));
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query heatmap quality", e);
        }
    }

    private Site site(UUID id) {
        Site site = sites.site(id);
        access.member(site.organization.id);
        return site;
    }

    private Variant variant(UUID siteId, UUID id) {
        String sql =
                "select id,page_url,layout_version,target_id,viewport_width,viewport_height,content_width,content_height,created_at from heatmap_variant where site_id=? and id=?";
        try (Connection c = dataSource.getConnection();
                PreparedStatement s = c.prepareStatement(sql)) {
            s.setObject(1, siteId);
            s.setObject(2, id);
            try (ResultSet r = s.executeQuery()) {
                if (!r.next())
                    throw new ControlPlaneException(404, "HEATMAP_VARIANT_NOT_FOUND", "Heatmap variant not found");
                return new Variant(
                        r.getObject(1, UUID.class),
                        r.getString(2),
                        r.getString(3),
                        r.getString(4),
                        r.getInt(5),
                        r.getInt(6),
                        r.getInt(7),
                        r.getInt(8),
                        r.getTimestamp(9).toInstant());
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query heatmap variant", e);
        }
    }

    public record Variant(
            UUID id,
            String pageUrl,
            String layoutVersion,
            String targetId,
            int viewportWidth,
            int viewportHeight,
            int contentWidth,
            int contentHeight,
            Instant createdAt) {}

    public record Page(String url, long variants) {}

    public record Cell(int x, int y, long count) {}

    public record Depth(int bin, long reached, long instances, double ratio) {}

    private record Sampling(int minimum, int maximum) {}

    private record Quality(long truncatedInstances, long dropped) {}

    public record Stats(
            Variant variant,
            String type,
            int gridSize,
            long instances,
            long rawCount,
            int sampleRateMinimum,
            int sampleRateMaximum,
            long truncatedInstances,
            long dropped,
            List<Cell> cells,
            List<Depth> depth,
            Instant updatedAt) {}
}
