package io.seeray.lens.application;

import io.seeray.lens.domain.site.Site;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.*;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import javax.sql.DataSource;

/** Aggregated JavaScript crash diagnostics. No visitor or session identifiers leave this service. */
@ApplicationScoped
public class CrashAnalyticsService {
    private final DataSource dataSource;
    private final SiteService sites;

    @Inject
    public CrashAnalyticsService(DataSource dataSource, SiteService sites) {
        this.dataSource = dataSource;
        this.sites = sites;
    }

    public Report report(UUID siteId, AnalyticsQueryService.Range range) {
        Site site = sites.site(siteId);
        String base =
                """
                from raw_event e
                where e.site_id=? and e.event_type='client_error'
                  and (e.occurred_at at time zone ?)::date between ? and ?
                  and e.event_data->'data'->>'fingerprint' ~ '^[0-9a-f]{16}$'
                """;
        long occurrences;
        int issueCount;
        try (Connection connection = dataSource.getConnection()) {
            try (PreparedStatement summary = connection.prepareStatement(
                    "select count(*)::bigint,count(distinct e.event_data->'data'->>'fingerprint')::integer " + base)) {
                bind(summary, siteId, site.timezone, range.from(), range.to());
                try (ResultSet result = summary.executeQuery()) {
                    result.next();
                    occurrences = result.getLong(1);
                    issueCount = result.getInt(2);
                }
            }
            List<Row> rows = new ArrayList<>();
            String query =
                    """
                    select e.event_data->'data'->>'fingerprint' fingerprint,
                      e.event_data->'data'->>'errorName' error_name,
                      e.event_data->'data'->>'message' message,
                      e.event_data->'data'->>'sourcePath' source_path,
                      max(case when e.event_data->'data'->>'line' ~ '^[0-9]{1,8}$'
                        then (e.event_data->'data'->>'line')::integer end) line,
                      max(case when e.event_data->'data'->>'column' ~ '^[0-9]{1,8}$'
                        then (e.event_data->'data'->>'column')::integer end) column,
                      max(e.event_data->'data'->>'functionName') function_name,
                      count(*)::bigint occurrences,count(distinct e.page_path)::integer affected_pages,
                      coalesce(string_agg(distinct coalesce(e.event_data->'context'->>'browser','Other'), ', ' order by coalesce(e.event_data->'context'->>'browser','Other')), 'Other') browsers,
                      coalesce(string_agg(distinct coalesce(e.event_data->'data'->>'platform','web'), ', ' order by coalesce(e.event_data->'data'->>'platform','web')), 'web') platforms,
                      min(e.occurred_at) first_seen,max(e.occurred_at) last_seen,count(*) over() total_rows
                    """
                            + base
                            + """
                    group by fingerprint,error_name,message,source_path
                    order by count(*) desc,max(e.occurred_at) desc,fingerprint
                    limit 100
                    """;
            try (PreparedStatement statement = connection.prepareStatement(query)) {
                bind(statement, siteId, site.timezone, range.from(), range.to());
                try (ResultSet result = statement.executeQuery()) {
                    int totalRows = 0;
                    while (result.next()) {
                        totalRows = result.getInt(14);
                        int line = result.getInt(5);
                        Integer lineNumber = result.wasNull() ? null : line;
                        int column = result.getInt(6);
                        Integer columnNumber = result.wasNull() ? null : column;
                        rows.add(new Row(
                                result.getString(1),
                                result.getString(2),
                                result.getString(3),
                                result.getString(4),
                                lineNumber,
                                columnNumber,
                                result.getString(7),
                                result.getLong(8),
                                result.getInt(9),
                                result.getString(10),
                                result.getString(11),
                                result.getTimestamp(12).toInstant(),
                                result.getTimestamp(13).toInstant()));
                    }
                    return new Report(
                            range.from(),
                            range.to(),
                            occurrences,
                            issueCount,
                            List.copyOf(rows),
                            totalRows > rows.size());
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query crash analytics", error);
        }
    }

    private static void bind(PreparedStatement statement, UUID siteId, String timezone, LocalDate from, LocalDate to)
            throws SQLException {
        statement.setObject(1, siteId);
        statement.setString(2, timezone);
        statement.setObject(3, from);
        statement.setObject(4, to);
    }

    public record Report(
            LocalDate from, LocalDate to, long occurrences, int issueCount, List<Row> rows, boolean hasMore) {}

    public record Row(
            String fingerprint,
            String errorName,
            String message,
            String sourcePath,
            Integer line,
            Integer column,
            String functionName,
            long occurrences,
            int affectedPages,
            String browsers,
            String platforms,
            Instant firstSeen,
            Instant lastSeen) {}
}
