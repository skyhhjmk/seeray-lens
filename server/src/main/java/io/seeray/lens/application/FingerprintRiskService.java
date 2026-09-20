package io.seeray.lens.application;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.Instant;
import java.util.UUID;
import javax.sql.DataSource;

/** Reads privacy-safe browser fingerprint risk summaries without exposing the key. */
@ApplicationScoped
public class FingerprintRiskService {
    private final DataSource dataSource;

    @Inject
    public FingerprintRiskService(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    public Risk risk(UUID siteId, String visitorId) {
        if (siteId == null || visitorId == null || visitorId.isBlank()) return Risk.none();
        String sql = """
                with current_keys as (
                  select distinct fingerprint_key from fingerprint_observation o
                  join site s on s.id=o.site_id and s.fingerprint_risk_enabled
                  where o.site_id=? and o.client_visitor_id=?
                ), related as (
                  select o.client_visitor_id,o.user_id_hash,o.observed_at
                  from fingerprint_observation o join current_keys k using(fingerprint_key)
                  where o.site_id=?
                )
                select count(distinct client_visitor_id) filter (where client_visitor_id<>?),
                       count(distinct user_id_hash) filter (where user_id_hash is not null),
                       max(observed_at)
                from related
                """;
        try (Connection connection = dataSource.getConnection(); PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, siteId);
            statement.setString(2, visitorId);
            statement.setObject(3, siteId);
            statement.setString(4, visitorId);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) return Risk.none();
                int visitors = rows.getInt(1);
                int accounts = rows.getInt(2);
                Timestamp last = rows.getTimestamp(3);
                String level = accounts > 1 ? "multiple_accounts" : visitors > 0 ? "possible_same_browser" : "none";
                return new Risk(level, visitors, accounts, last == null ? null : last.toInstant(),
                        visitors > 0 || accounts > 0 ? "medium" : "none");
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query fingerprint risk", error);
        }
    }

    public record Risk(String level, int relatedVisitorCount, int relatedAccountCount,
                       Instant lastObservedAt, String confidence) {
        static Risk none() { return new Risk("none", 0, 0, null, "none"); }
    }
}
