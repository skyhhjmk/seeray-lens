package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.util.*;
import javax.sql.DataSource;

/** Validates campaign cost imports and compares them with site-local acquisition and goal facts. */
@ApplicationScoped
public class CampaignCostService {
    private static final int MAX_IMPORT_ROWS = 5_000;
    private static final int MAX_IMPORT_CHARACTERS = 2 * 1024 * 1024;
    private static final Set<String> PLATFORMS =
            Set.of("google_ads", "microsoft_ads", "meta_ads", "tiktok_ads", "linkedin_ads", "x_ads", "other");
    private static final Set<String> CURRENCIES = Currency.getAvailableCurrencies().stream()
            .map(Currency::getCurrencyCode)
            .collect(java.util.stream.Collectors.toUnmodifiableSet());
    private static final Comparator<NormalizedRow> ROW_ORDER = Comparator.comparing(NormalizedRow::date)
            .thenComparing(NormalizedRow::platform)
            .thenComparing(NormalizedRow::source)
            .thenComparing(NormalizedRow::medium)
            .thenComparing(NormalizedRow::campaign)
            .thenComparing(NormalizedRow::currency);

    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final SegmentService segments;
    private final AttributionQueryService attribution;

    @Inject
    public CampaignCostService(
            DataSource dataSource,
            SiteService sites,
            WorkspaceAccess access,
            SegmentService segments,
            AttributionQueryService attribution) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
        this.segments = segments;
        this.attribution = attribution;
    }

    public ImportHistory imports(UUID siteId) {
        Site site = readableSite(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        List<ImportBatch> batches = new ArrayList<>();
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "select id,file_name,row_count,imported_at from analytics_campaign_cost_import "
                                + "where site_id=? order by imported_at desc,id desc limit 30")) {
            statement.setObject(1, siteId);
            try (var rows = statement.executeQuery()) {
                while (rows.next())
                    batches.add(new ImportBatch(
                            rows.getObject(1, UUID.class),
                            rows.getString(2),
                            rows.getInt(3),
                            rows.getTimestamp(4).toInstant()));
            }
        } catch (Exception error) {
            throw new IllegalStateException("Could not list campaign cost imports", error);
        }
        return new ImportHistory(canManage, site.timezone, List.copyOf(batches));
    }

    @Transactional
    public ImportResult importRows(UUID siteId, String fileName, List<RowInput> inputRows) {
        writableSite(siteId);
        String normalizedFileName = normalizeFileName(fileName);
        List<NormalizedRow> rows = normalizeRows(inputRows);
        String contentHash = hash(rows);
        UUID importId = UuidV7.next();
        try (var connection = dataSource.getConnection();
                var createImport = connection.prepareStatement(
                        "insert into analytics_campaign_cost_import(id,site_id,file_name,file_hash,row_count,actor_user_id) "
                                + "values(?,?,?,?,?,?) on conflict(site_id,file_hash) do nothing")) {
            createImport.setObject(1, importId);
            createImport.setObject(2, siteId);
            createImport.setString(3, normalizedFileName);
            createImport.setString(4, contentHash);
            createImport.setInt(5, rows.size());
            createImport.setObject(6, access.userId());
            int inserted = createImport.executeUpdate();
            if (inserted == 0) {
                try (var existing = connection.prepareStatement(
                        "select id,row_count,imported_at from analytics_campaign_cost_import "
                                + "where site_id=? and file_hash=?")) {
                    existing.setObject(1, siteId);
                    existing.setString(2, contentHash);
                    try (var result = existing.executeQuery()) {
                        if (!result.next()) throw new IllegalStateException("Duplicate import disappeared");
                        return new ImportResult(
                                result.getObject(1, UUID.class),
                                result.getInt(2),
                                true,
                                result.getTimestamp(3).toInstant());
                    }
                }
            }
            try (var upsert = connection.prepareStatement(
                    "insert into analytics_campaign_cost(site_id,business_date,platform,source,medium,campaign,currency,"
                            + "impressions,clicks,cost_amount,import_id) values(?,?,?,?,?,?,?,?,?,?,?) "
                            + "on conflict(site_id,business_date,platform,source,medium,campaign,currency) do update set "
                            + "impressions=excluded.impressions,clicks=excluded.clicks,cost_amount=excluded.cost_amount,"
                            + "import_id=excluded.import_id,updated_at=now()")) {
                for (NormalizedRow row : rows) {
                    upsert.setObject(1, siteId);
                    upsert.setObject(2, row.date());
                    upsert.setString(3, row.platform());
                    upsert.setString(4, row.source());
                    upsert.setString(5, row.medium());
                    upsert.setString(6, row.campaign());
                    upsert.setString(7, row.currency());
                    upsert.setLong(8, row.impressions());
                    upsert.setLong(9, row.clicks());
                    upsert.setBigDecimal(10, row.cost());
                    upsert.setObject(11, importId);
                    upsert.addBatch();
                }
                upsert.executeBatch();
            }
            return new ImportResult(importId, rows.size(), false, java.time.Instant.now());
        } catch (Exception error) {
            if (error instanceof ControlPlaneException controlled) throw controlled;
            throw new IllegalStateException("Could not import campaign costs", error);
        }
    }

    public Report report(
            UUID siteId,
            AnalyticsQueryService.Range range,
            UUID segmentId,
            UUID goalId,
            String model,
            int lookbackDays) {
        Site site = readableSite(siteId);
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        Map<CampaignDimensions, Long> sessions = sessions(site, range, filter);
        Map<CampaignDimensions, AttributionValue> attributed = new HashMap<>();
        AttributionQueryService.Report attributionReport =
                attribution.report(siteId, range, segmentId, goalId, model, lookbackDays);
        for (AttributionQueryService.Row row : attributionReport.rows()) {
            CampaignDimensions key = new CampaignDimensions(row.source(), row.medium(), row.campaign());
            AttributionValue current = attributed.getOrDefault(key, AttributionValue.ZERO);
            attributed.put(
                    key,
                    new AttributionValue(
                            current.conversions().add(row.attributedConversions()),
                            current.value().add(row.attributedValue())));
        }

        List<CampaignCostRow> result = new ArrayList<>();
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "select platform,source,medium,campaign,currency,sum(impressions),sum(clicks),sum(cost_amount) "
                                + "from analytics_campaign_cost where site_id=? and business_date between ? and ? "
                                + "group by platform,source,medium,campaign,currency "
                                + "order by sum(cost_amount) desc,source,medium,campaign,currency")) {
            statement.setObject(1, siteId);
            statement.setObject(2, range.from());
            statement.setObject(3, range.to());
            try (var rows = statement.executeQuery()) {
                while (rows.next()) {
                    String source = rows.getString(2);
                    String medium = rows.getString(3);
                    String campaign = rows.getString(4);
                    CampaignDimensions dimensions = new CampaignDimensions(source, medium, campaign);
                    long clicks = rows.getLong(7);
                    BigDecimal cost = rows.getBigDecimal(8);
                    AttributionValue value = attributed.getOrDefault(dimensions, AttributionValue.ZERO);
                    result.add(new CampaignCostRow(
                            rows.getString(1),
                            source,
                            medium,
                            campaign,
                            rows.getString(5).trim(),
                            rows.getLong(6),
                            clicks,
                            cost,
                            sessions.getOrDefault(dimensions, 0L),
                            value.conversions(),
                            value.value(),
                            divide(cost, clicks),
                            divide(cost, value.conversions()),
                            cost.signum() == 0 ? null : divide(value.value(), cost)));
                }
            }
        } catch (Exception error) {
            throw new IllegalStateException("Could not query campaign cost report", error);
        }
        return new Report(
                range.from(),
                range.to(),
                attributionReport.model(),
                attributionReport.lookbackDays(),
                List.copyOf(result));
    }

    private Map<CampaignDimensions, Long> sessions(
            Site site, AnalyticsQueryService.Range range, SegmentService.SessionFilter filter) {
        Map<CampaignDimensions, Long> result = new HashMap<>();
        String sql = "select s.initial_utm_source,s.initial_utm_medium,s.initial_utm_campaign,count(*) "
                + "from analytics_session s where s.site_id=? and (s.started_at at time zone ?)::date between ? and ? "
                + "and (" + filter.expression() + ") and (" + AcquisitionClassifier.channelSql("s")
                + ")='campaign' group by s.initial_utm_source,s.initial_utm_medium,s.initial_utm_campaign";
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(sql)) {
            statement.setObject(1, site.id);
            statement.setString(2, site.timezone);
            statement.setObject(3, range.from());
            statement.setObject(4, range.to());
            int index = 5;
            for (Object value : filter.values()) statement.setObject(index++, value);
            try (var rows = statement.executeQuery()) {
                while (rows.next())
                    result.put(
                            new CampaignDimensions(rows.getString(1), rows.getString(2), rows.getString(3)),
                            rows.getLong(4));
            }
            return result;
        } catch (Exception error) {
            throw new IllegalStateException("Could not load campaign session counts", error);
        }
    }

    private Site readableSite(UUID siteId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        return site;
    }

    private Site writableSite(UUID siteId) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return site;
    }

    private List<NormalizedRow> normalizeRows(List<RowInput> values) {
        if (values == null || values.isEmpty() || values.size() > MAX_IMPORT_ROWS)
            throw invalid("Choose a CSV with 1 to " + MAX_IMPORT_ROWS + " campaign rows.");
        List<NormalizedRow> result = new ArrayList<>();
        Set<RowKey> keys = new HashSet<>();
        long inputCharacters = 0;
        for (int i = 0; i < values.size(); i++) {
            RowInput value = values.get(i);
            int rowNumber = i + 2;
            if (value == null) throw invalid("Row " + rowNumber + " is empty.");
            inputCharacters += length(value.date())
                    + length(value.platform())
                    + length(value.source())
                    + length(value.medium())
                    + length(value.campaign())
                    + length(value.currency())
                    + (value.cost() == null ? 0 : value.cost().toString().length())
                    + 44;
            if (inputCharacters > MAX_IMPORT_CHARACTERS)
                throw invalid("Campaign cost imports must be 2 MiB or smaller.");
            LocalDate date;
            try {
                if (value.date() == null || !value.date().matches("\\d{4}-\\d{2}-\\d{2}")) throw new Exception();
                date = LocalDate.parse(value.date());
            } catch (Exception error) {
                throw invalid("Row " + rowNumber + ": date must use YYYY-MM-DD.");
            }
            String platform =
                    value.platform() == null ? "" : value.platform().trim().toLowerCase(Locale.ROOT);
            if (!PLATFORMS.contains(platform))
                throw invalid("Row " + rowNumber + ": choose a supported advertising platform.");
            String source = field(value.source(), 128, "source", rowNumber);
            String medium = field(value.medium(), 128, "medium", rowNumber);
            String campaign = field(value.campaign(), 256, "campaign", rowNumber);
            String currency =
                    value.currency() == null ? "" : value.currency().trim().toUpperCase(Locale.ROOT);
            if (!currency.matches("[A-Z]{3}") || !CURRENCIES.contains(currency))
                throw invalid("Row " + rowNumber + ": currency must be a supported ISO 4217 code.");
            BigDecimal cost = value.cost();
            if (cost == null
                    || cost.signum() < 0
                    || cost.scale() > 6
                    || cost.precision() > 18
                    || cost.precision() - cost.scale() > 12)
                throw invalid("Row " + rowNumber + ": cost must be a non-negative amount with up to 6 decimals.");
            if (value.clicks() == null || value.clicks() < 0 || value.clicks() > 1_000_000_000_000L)
                throw invalid("Row " + rowNumber + ": clicks must be a non-negative whole number.");
            if (value.impressions() == null || value.impressions() < 0 || value.impressions() > 1_000_000_000_000L)
                throw invalid("Row " + rowNumber + ": impressions must be a non-negative whole number.");
            RowKey key = new RowKey(date, platform, source, medium, campaign, currency);
            if (!keys.add(key)) throw invalid("Row " + rowNumber + ": this date and campaign appears more than once.");
            result.add(new NormalizedRow(
                    date,
                    platform,
                    source,
                    medium,
                    campaign,
                    currency,
                    cost.stripTrailingZeros(),
                    value.clicks(),
                    value.impressions()));
        }
        result.sort(ROW_ORDER);
        return List.copyOf(result);
    }

    private static String normalizeFileName(String value) {
        if (value == null || value.isBlank()) throw invalid("The selected file name is missing.");
        String name = value.replace('\\', '/');
        name = name.substring(name.lastIndexOf('/') + 1).strip().replaceAll("[\\p{Cc}]", "");
        if (name.isBlank() || name.length() > 255) throw invalid("The selected file name is invalid.");
        return name;
    }

    private static String field(String value, int maximum, String label, int row) {
        String result = value == null ? "" : value.strip();
        if (result.isBlank() || result.length() > maximum || result.chars().anyMatch(Character::isISOControl))
            throw invalid("Row " + row + ": " + label + " is required and must be at most " + maximum + " characters.");
        return result;
    }

    private static int length(String value) {
        return value == null ? 0 : value.length();
    }

    private static String hash(List<NormalizedRow> rows) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            for (NormalizedRow row : rows) {
                for (String value : List.of(
                        row.date().toString(),
                        row.platform(),
                        row.source(),
                        row.medium(),
                        row.campaign(),
                        row.currency(),
                        row.cost().toPlainString(),
                        Long.toString(row.clicks()),
                        Long.toString(row.impressions()))) {
                    digest.update(value.getBytes(StandardCharsets.UTF_8));
                    digest.update((byte) 0x1f);
                }
                digest.update((byte) 0x0a);
            }
            return HexFormat.of().formatHex(digest.digest());
        } catch (Exception error) {
            throw new IllegalStateException("SHA-256 is not available", error);
        }
    }

    private static BigDecimal divide(BigDecimal numerator, long denominator) {
        return denominator == 0 ? null : numerator.divide(BigDecimal.valueOf(denominator), 6, RoundingMode.HALF_UP);
    }

    private static BigDecimal divide(BigDecimal numerator, BigDecimal denominator) {
        return denominator.signum() == 0 ? null : numerator.divide(denominator, 6, RoundingMode.HALF_UP);
    }

    private static ControlPlaneException invalid(String message) {
        return new ControlPlaneException(400, "AD_COST_IMPORT_INVALID", message);
    }

    public record RowInput(
            String date,
            String platform,
            String source,
            String medium,
            String campaign,
            String currency,
            BigDecimal cost,
            Long clicks,
            Long impressions) {}

    public record ImportBatch(UUID id, String fileName, int rowCount, java.time.Instant importedAt) {}

    public record ImportHistory(boolean canManage, String timezone, List<ImportBatch> imports) {}

    public record ImportResult(UUID id, int rowsImported, boolean alreadyImported, java.time.Instant importedAt) {}

    public record Report(LocalDate from, LocalDate to, String model, int lookbackDays, List<CampaignCostRow> rows) {}

    public record CampaignCostRow(
            String platform,
            String source,
            String medium,
            String campaign,
            String currency,
            long impressions,
            long clicks,
            BigDecimal cost,
            long sessions,
            BigDecimal attributedConversions,
            BigDecimal attributedGoalValue,
            BigDecimal costPerClick,
            BigDecimal costPerAttributedConversion,
            BigDecimal goalValuePerSpend) {}

    private record CampaignDimensions(String source, String medium, String campaign) {}

    private record AttributionValue(BigDecimal conversions, BigDecimal value) {
        static final AttributionValue ZERO = new AttributionValue(BigDecimal.ZERO, BigDecimal.ZERO);
    }

    private record RowKey(
            LocalDate date, String platform, String source, String medium, String campaign, String currency) {}

    private record NormalizedRow(
            LocalDate date,
            String platform,
            String source,
            String medium,
            String campaign,
            String currency,
            BigDecimal cost,
            long clicks,
            long impressions) {}
}
