package io.seeray.lens.application;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.*;
import java.util.*;
import javax.sql.DataSource;

/** Applies site-level raw and aggregate retention without rebuilding or discarding retained history. */
@ApplicationScoped
public class RawAnalyticsRetentionService {
    private static final int BATCH_SIZE = 10_000;
    private final DataSource dataSource;

    @Inject
    public RawAnalyticsRetentionService(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Transactional
    public CleanupSummary clean() {
        try (Connection connection = dataSource.getConnection()) {
            List<Policy> policies = policies(connection);
            long rawEvents = 0;
            long aggregateRows = 0;
            long sessions = 0;
            long visitors = 0;
            Instant now = Instant.now();
            for (Policy policy : policies) {
                Instant rawCutoff = now.minus(Duration.ofDays(policy.rawRetentionDays));
                LocalDate aggregateCutoff = LocalDate.now(policy.zone).minusDays(policy.aggregateRetentionDays);
                rawEvents += deleteRawEvents(connection, policy.siteId, rawCutoff);
                aggregateRows += deleteDatedAggregates(connection, policy.siteId, aggregateCutoff);
                Instant aggregateInstantCutoff =
                        aggregateCutoff.atStartOfDay(policy.zone).toInstant();
                aggregateRows += deleteExpiredOfflineConversions(connection, policy.siteId, aggregateInstantCutoff);
                sessions += deleteOldSessions(connection, policy.siteId, aggregateInstantCutoff);
                visitors += deleteOrphanVisitors(connection, policy.siteId);
                refreshVisitorStats(connection, policy.siteId);
            }
            return new CleanupSummary(policies.size(), rawEvents, aggregateRows, sessions, visitors);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not clean expired analytics data", error);
        }
    }

    private static List<Policy> policies(Connection connection) throws SQLException {
        List<Policy> result = new ArrayList<>();
        try (PreparedStatement statement = connection.prepareStatement(
                        "select id,timezone,raw_retention_days,aggregate_retention_days from site");
                ResultSet rows = statement.executeQuery()) {
            while (rows.next())
                result.add(new Policy(
                        rows.getObject(1, UUID.class), ZoneId.of(rows.getString(2)), rows.getInt(3), rows.getInt(4)));
        }
        return result;
    }

    private static long deleteRawEvents(Connection connection, UUID siteId, Instant cutoff) throws SQLException {
        return deleteInBatches(
                connection,
                "delete from raw_event where ingest_id in (select ingest_id from raw_event where site_id=? and received_at < ? order by received_at,ingest_id limit ?)",
                statement -> {
                    statement.setObject(1, siteId);
                    statement.setTimestamp(2, Timestamp.from(cutoff));
                });
    }

    private static long deleteDatedAggregates(Connection connection, UUID siteId, LocalDate cutoff)
            throws SQLException {
        long deleted = 0;
        for (String table : List.of(
                "analytics_site_daily",
                "analytics_page_daily",
                "analytics_page_title_daily",
                "analytics_traffic_daily",
                "analytics_event_daily",
                "analytics_goal_daily",
                "analytics_goal_conversion_daily",
                "visitor_identity_day_fact",
                "visitor_day_fact")) {
            deleted += deleteInBatches(
                    connection,
                    "delete from " + table
                            + " where ctid in (select ctid from " + table
                            + " where site_id=? and business_date < ? order by business_date limit ?)",
                    statement -> {
                        statement.setObject(1, siteId);
                        statement.setObject(2, cutoff);
                    });
        }
        return deleted;
    }

    private static long deleteOldSessions(Connection connection, UUID siteId, Instant cutoff) throws SQLException {
        return deleteInBatches(
                connection,
                "delete from analytics_session where id in (select id from analytics_session where site_id=? and started_at < ? order by started_at,id limit ?)",
                statement -> {
                    statement.setObject(1, siteId);
                    statement.setTimestamp(2, Timestamp.from(cutoff));
                });
    }

    private static long deleteExpiredOfflineConversions(Connection connection, UUID siteId, Instant cutoff)
            throws SQLException {
        return deleteInBatches(
                connection,
                "delete from analytics_offline_conversion where id in (select id from analytics_offline_conversion where site_id=? and converted_at < ? order by converted_at,id limit ?)",
                statement -> {
                    statement.setObject(1, siteId);
                    statement.setTimestamp(2, Timestamp.from(cutoff));
                });
    }

    private static long deleteOrphanVisitors(Connection connection, UUID siteId) throws SQLException {
        return deleteInBatches(
                connection,
                "delete from analytics_visitor where id in (select v.id from analytics_visitor v where v.site_id=? and not exists (select 1 from analytics_session s where s.visitor_id=v.id) limit ?)",
                statement -> statement.setObject(1, siteId));
    }

    private static void refreshVisitorStats(Connection connection, UUID siteId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "update analytics_visitor v set first_seen_at=s.first_started,last_seen_at=s.last_activity,first_session_at=s.first_started,last_session_at=s.last_started,session_count=s.sessions from (select visitor_id,min(started_at) first_started,max(started_at) last_started,max(last_activity_at) last_activity,count(*)::integer sessions from analytics_session where site_id=? group by visitor_id) s where v.site_id=? and v.id=s.visitor_id")) {
            statement.setObject(1, siteId);
            statement.setObject(2, siteId);
            statement.executeUpdate();
        }
    }

    private static long deleteInBatches(Connection connection, String sql, Binder binder) throws SQLException {
        long total = 0;
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            while (true) {
                binder.bind(statement);
                statement.setInt(statement.getParameterMetaData().getParameterCount(), BATCH_SIZE);
                int deleted = statement.executeUpdate();
                total += deleted;
                if (deleted < BATCH_SIZE) return total;
            }
        }
    }

    private record Policy(UUID siteId, ZoneId zone, int rawRetentionDays, int aggregateRetentionDays) {}

    @FunctionalInterface
    private interface Binder {
        void bind(PreparedStatement statement) throws SQLException;
    }

    public record CleanupSummary(
            int sitesProcessed,
            long rawEventsDeleted,
            long aggregateRowsDeleted,
            long sessionsDeleted,
            long visitorsDeleted) {}
}
