package io.seeray.lens.application;

import io.seeray.lens.domain.common.UuidV7;
import jakarta.enterprise.context.ApplicationScoped;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.*;
import java.util.UUID;

@ApplicationScoped
public class HeatmapVariantService {
    public UUID resolve(Connection connection, UUID siteId, Identity identity) throws Exception {
        String hash = digest(identity.pageUrl()
                + "\n"
                + identity.layoutVersion()
                + "\n"
                + identity.targetId()
                + "\n"
                + identity.viewportWidth()
                + "\n"
                + identity.viewportHeight()
                + "\n"
                + identity.contentWidth()
                + "\n"
                + identity.contentHeight());
        String lookup =
                "select id from heatmap_variant where site_id=? and page_hash=? and layout_version=? and target_id=? and viewport_width=? and viewport_height=? and content_width=? and content_height=?";
        try (PreparedStatement statement = connection.prepareStatement(lookup)) {
            bind(statement, siteId, hash, identity);
            try (ResultSet rows = statement.executeQuery()) {
                if (rows.next()) return rows.getObject(1, UUID.class);
            }
        }
        try (PreparedStatement statement = connection.prepareStatement(
                "insert into heatmap_variant (id,site_id,page_url,page_hash,layout_version,target_id,viewport_width,viewport_height,content_width,content_height) values (?,?,?,?,?,?,?,?,?,?) on conflict do nothing")) {
            statement.setObject(1, UuidV7.next());
            statement.setObject(2, siteId);
            statement.setString(3, identity.pageUrl());
            statement.setString(4, hash);
            statement.setString(5, identity.layoutVersion());
            statement.setString(6, identity.targetId());
            statement.setInt(7, identity.viewportWidth());
            statement.setInt(8, identity.viewportHeight());
            statement.setInt(9, identity.contentWidth());
            statement.setInt(10, identity.contentHeight());
            statement.executeUpdate();
        }
        try (PreparedStatement statement = connection.prepareStatement(lookup)) {
            bind(statement, siteId, hash, identity);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) throw new SQLException("Could not resolve heatmap variant");
                return rows.getObject(1, UUID.class);
            }
        }
    }

    private static void bind(PreparedStatement statement, UUID siteId, String hash, Identity identity)
            throws SQLException {
        statement.setObject(1, siteId);
        statement.setString(2, hash);
        statement.setString(3, identity.layoutVersion());
        statement.setString(4, identity.targetId());
        statement.setInt(5, identity.viewportWidth());
        statement.setInt(6, identity.viewportHeight());
        statement.setInt(7, identity.contentWidth());
        statement.setInt(8, identity.contentHeight());
    }

    private static String digest(String value) throws Exception {
        StringBuilder result = new StringBuilder(64);
        for (byte item : MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8))) {
            result.append(String.format("%02x", item));
        }
        return result.toString();
    }

    public record Identity(
            String pageUrl,
            String layoutVersion,
            String targetId,
            int viewportWidth,
            int viewportHeight,
            int contentWidth,
            int contentHeight) {}
}
