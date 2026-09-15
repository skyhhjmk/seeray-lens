package io.seeray.lens.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.*;
import java.time.*;
import java.util.*;
import javax.sql.DataSource;

/** The raw-batch row lock makes redelivery and concurrent workers idempotent. */
@ApplicationScoped
public class HeatmapAggregationService {
    private final DataSource dataSource;
    private final ObjectMapper mapper;

    @Inject
    public HeatmapAggregationService(DataSource dataSource, ObjectMapper mapper) {
        this.dataSource = dataSource;
        this.mapper = mapper;
    }

    @Transactional
    public int processPending(int limit) {
        try (Connection c = dataSource.getConnection()) {
            List<Batch> batches = new ArrayList<>();
            try (PreparedStatement s = c.prepareStatement(
                    "select id,site_id,payload,received_at,effective_sample_rate from heatmap_raw_batch where processed_at is null order by received_at for update skip locked limit ?")) {
                s.setInt(1, limit);
                try (ResultSet rows = s.executeQuery()) {
                    while (rows.next())
                        batches.add(new Batch(
                                rows.getObject(1, UUID.class),
                                rows.getObject(2, UUID.class),
                                rows.getString(3),
                                rows.getTimestamp(4).toInstant(),
                                rows.getInt(5)));
                }
            }
            for (Batch batch : batches) {
                process(c, batch);
                try (PreparedStatement s = c.prepareStatement(
                        "update heatmap_raw_batch set processed_at=now(),failure_reason=null where id=?")) {
                    s.setObject(1, batch.id);
                    s.executeUpdate();
                }
            }
            return batches.size();
        } catch (Exception error) {
            throw new IllegalStateException("Could not aggregate heatmap batches", error);
        }
    }

    private void process(Connection c, Batch batch) throws Exception {
        Site site = Site.findById(batch.site);
        if (site == null) return;
        LocalDate date = batch.received.atZone(ZoneId.of(site.timezone)).toLocalDate();
        for (JsonNode event : mapper.readTree(batch.payload)) {
            TrackingSanitizer.CleanUrl page =
                    TrackingSanitizer.url(event.path("url").asText(), mapper);
            String url = page.scheme() + "://" + page.host() + page.path();
            UUID variant = variant(c, batch.site, url, event);
            UUID instance = UUID.fromString(event.path("instanceId").asText());
            String type = event.path("type").asText();
            if (type.equals("start"))
                startInstance(c, batch.site, instance, variant, date, batch.effectiveSampleRate, event);
            else updateInstanceQuality(c, batch.site, instance, variant, event);
            if (type.equals("click") || type.equals("move")) grid(c, batch.site, date, variant, event, type);
            if (type.equals("scroll")) scroll(c, batch.site, instance, date, variant, event);
        }
    }

    private UUID variant(Connection c, UUID site, String url, JsonNode e) throws Exception {
        String layout = e.path("layoutVersion").asText(),
                target = e.path("targetId").asText();
        int vw = e.path("viewportWidth").asInt(),
                vh = e.path("viewportHeight").asInt(),
                cw = e.path("contentWidth").asInt(),
                ch = e.path("contentHeight").asInt();
        String hash = digest(url + "\n" + layout + "\n" + target + "\n" + vw + "\n" + vh + "\n" + cw + "\n" + ch);
        String lookup =
                "select id from heatmap_variant where site_id=? and page_hash=? and layout_version=? and target_id=? and viewport_width=? and viewport_height=? and content_width=? and content_height=?";
        try (PreparedStatement s = c.prepareStatement(lookup)) {
            bind(s, site, hash, layout, target, vw, vh, cw, ch);
            try (ResultSet r = s.executeQuery()) {
                if (r.next()) return r.getObject(1, UUID.class);
            }
        }
        try (PreparedStatement s = c.prepareStatement(
                "insert into heatmap_variant (id,site_id,page_url,page_hash,layout_version,target_id,viewport_width,viewport_height,content_width,content_height) values (?,?,?,?,?,?,?,?,?,?) on conflict do nothing")) {
            s.setObject(1, UuidV7.next());
            s.setObject(2, site);
            s.setString(3, url);
            s.setString(4, hash);
            s.setString(5, layout);
            s.setString(6, target);
            s.setInt(7, vw);
            s.setInt(8, vh);
            s.setInt(9, cw);
            s.setInt(10, ch);
            s.executeUpdate();
        }
        try (PreparedStatement s = c.prepareStatement(lookup)) {
            bind(s, site, hash, layout, target, vw, vh, cw, ch);
            try (ResultSet r = s.executeQuery()) {
                r.next();
                return r.getObject(1, UUID.class);
            }
        }
    }

    private static void bind(
            PreparedStatement s, UUID site, String hash, String layout, String target, int vw, int vh, int cw, int ch)
            throws SQLException {
        s.setObject(1, site);
        s.setString(2, hash);
        s.setString(3, layout);
        s.setString(4, target);
        s.setInt(5, vw);
        s.setInt(6, vh);
        s.setInt(7, cw);
        s.setInt(8, ch);
    }

    private static void startInstance(
            Connection c,
            UUID site,
            UUID instance,
            UUID variant,
            LocalDate date,
            int effectiveSampleRate,
            JsonNode event)
            throws SQLException {
        try (PreparedStatement s = c.prepareStatement(
                "insert into heatmap_instance_fact (site_id,page_instance_id,variant_id,business_date,sample_rate,truncated,dropped_count) values (?,?,?,?,?,?,?) on conflict (site_id,page_instance_id,variant_id) do update set truncated=heatmap_instance_fact.truncated or excluded.truncated,dropped_count=greatest(heatmap_instance_fact.dropped_count,excluded.dropped_count)")) {
            s.setObject(1, site);
            s.setObject(2, instance);
            s.setObject(3, variant);
            s.setObject(4, date);
            s.setInt(5, effectiveSampleRate);
            s.setBoolean(6, event.path("truncated").asBoolean(false));
            s.setInt(7, event.path("dropped").asInt(0));
            s.executeUpdate();
        }
    }

    /** Non-start events must not create a denominator entry when the start record was lost. */
    private static void updateInstanceQuality(Connection c, UUID site, UUID instance, UUID variant, JsonNode event)
            throws SQLException {
        try (PreparedStatement s = c.prepareStatement(
                "update heatmap_instance_fact set truncated=heatmap_instance_fact.truncated or ?,dropped_count=greatest(heatmap_instance_fact.dropped_count,?) where site_id=? and page_instance_id=? and variant_id=?")) {
            s.setBoolean(1, event.path("truncated").asBoolean(false));
            s.setInt(2, event.path("dropped").asInt(0));
            s.setObject(3, site);
            s.setObject(4, instance);
            s.setObject(5, variant);
            s.executeUpdate();
        }
    }

    private static void grid(Connection c, UUID site, LocalDate date, UUID variant, JsonNode e, String type)
            throws SQLException {
        try (PreparedStatement s = c.prepareStatement(
                "insert into heatmap_grid_daily (site_id,business_date,variant_id,event_type,grid_x,grid_y,event_count) values (?,?,?,?,?,?,1) on conflict (site_id,business_date,variant_id,event_type,grid_x,grid_y) do update set event_count=heatmap_grid_daily.event_count+1")) {
            s.setObject(1, site);
            s.setObject(2, date);
            s.setObject(3, variant);
            s.setString(4, type);
            s.setInt(5, e.path("x").asInt() / 16);
            s.setInt(6, e.path("y").asInt() / 16);
            s.executeUpdate();
        }
    }

    private static void scroll(Connection c, UUID site, UUID instance, LocalDate date, UUID variant, JsonNode e)
            throws SQLException {
        for (JsonNode bin : e.path("scrollBins")) {
            try (PreparedStatement seen = c.prepareStatement(
                    "insert into heatmap_instance_scroll_bin (site_id,page_instance_id,variant_id,depth_bin) values (?,?,?,?) on conflict do nothing")) {
                seen.setObject(1, site);
                seen.setObject(2, instance);
                seen.setObject(3, variant);
                seen.setInt(4, bin.asInt());
                if (seen.executeUpdate() == 0) continue;
            }
            try (PreparedStatement count = c.prepareStatement(
                    "insert into heatmap_scroll_daily (site_id,business_date,variant_id,depth_bin,reached_count,instance_count) values (?,?,?,?,1,(select count(*) from heatmap_instance_fact where site_id=? and variant_id=? and business_date=?)) on conflict (site_id,business_date,variant_id,depth_bin) do update set reached_count=heatmap_scroll_daily.reached_count+1,instance_count=excluded.instance_count")) {
                count.setObject(1, site);
                count.setObject(2, date);
                count.setObject(3, variant);
                count.setInt(4, bin.asInt());
                count.setObject(5, site);
                count.setObject(6, variant);
                count.setObject(7, date);
                count.executeUpdate();
            }
        }
    }

    private static String digest(String value) throws Exception {
        byte[] bytes = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
        StringBuilder result = new StringBuilder(64);
        for (byte valueByte : bytes) result.append(String.format("%02x", valueByte));
        return result.toString();
    }

    private record Batch(UUID id, UUID site, String payload, Instant received, int effectiveSampleRate) {}
}
