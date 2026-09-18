package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.*;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.*;
import java.util.Currency;
import javax.sql.DataSource;

/** Privacy-preserving click-id joins for operator-imported, goal-scoped offline conversions. */
@ApplicationScoped
public class OfflineConversionService {
    private static final int MAX_IMPORT_ROWS = 5_000;
    private static final int MAX_GOOGLE_ADS_ROWS = 2_000;
    private static final int MAX_IMPORT_CHARACTERS = 2 * 1024 * 1024;
    private static final Set<String> PLATFORMS =
            Set.of("google_ads", "microsoft_ads", "meta_ads", "tiktok_ads", "linkedin_ads", "x_ads");
    private static final Set<String> MODELS =
            Set.of("first_touch", "last_touch", "linear", "position_based", "time_decay");
    private static final Set<Integer> LOOKBACK_DAYS = Set.of(7, 30, 90);

    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final SegmentService segments;
    private final GoogleAdsDataManagerGateway googleAds;

    @Inject
    public OfflineConversionService(
            DataSource dataSource,
            SiteService sites,
            WorkspaceAccess access,
            SegmentService segments,
            GoogleAdsDataManagerGateway googleAds) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
        this.segments = segments;
        this.googleAds = googleAds;
    }

    public GoogleAdsConfigView googleAdsConfig(UUID siteId) {
        Site site = readableSite(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select customer_id,login_customer_id,conversion_action_id,currency_code,updated_at "
                                + "from analytics_google_ads_conversion_config where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) return new GoogleAdsConfigView(canManage, false, null, null, null, null, null);
                return new GoogleAdsConfigView(
                        canManage,
                        true,
                        row.getString(1),
                        row.getString(2),
                        row.getString(3),
                        row.getString(4),
                        row.getTimestamp(5).toInstant());
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read Google Ads conversion configuration", error);
        }
    }

    @Transactional
    public GoogleAdsConfigView saveGoogleAdsConfig(UUID siteId, GoogleAdsConfigInput input) {
        writableSite(siteId);
        String customerId = customerId(input.customerId(), "Google Ads customer ID");
        String loginCustomerId =
                input.loginCustomerId() == null || input.loginCustomerId().isBlank()
                        ? null
                        : customerId(input.loginCustomerId(), "Google Ads manager customer ID");
        String actionId = input.conversionActionId() == null
                ? ""
                : input.conversionActionId().trim();
        if (!actionId.matches("[0-9]{1,20}")) throw invalid("Conversion action ID must contain 1 to 20 digits.");
        String currencyCode =
                input.currencyCode() == null ? "" : input.currencyCode().trim().toUpperCase(Locale.ROOT);
        try {
            Currency.getInstance(currencyCode);
        } catch (IllegalArgumentException error) {
            throw invalid("Choose a valid three-letter ISO currency code.");
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_google_ads_conversion_config(site_id,customer_id,login_customer_id,"
                                + "conversion_action_id,currency_code,updated_by,updated_at) values(?,?,?,?,?,?,now()) "
                                + "on conflict(site_id) do update set customer_id=excluded.customer_id,"
                                + "login_customer_id=excluded.login_customer_id,"
                                + "conversion_action_id=excluded.conversion_action_id,currency_code=excluded.currency_code,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setString(2, customerId);
            statement.setString(3, loginCustomerId);
            statement.setString(4, actionId);
            statement.setString(5, currencyCode);
            statement.setObject(6, access.userId());
            statement.executeUpdate();
            return googleAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save Google Ads conversion configuration", error);
        }
    }

    public GoogleAdsTransferResult transferToGoogleAds(
            UUID siteId, GoogleAdsTransferInput input, boolean validateOnly) {
        writableSite(siteId);
        GoogleAdsDestination destination = googleAdsDestination(siteId);
        if (input == null
                || input.rows() == null
                || input.rows().isEmpty()
                || input.rows().size() > MAX_GOOGLE_ADS_ROWS)
            throw invalid("Choose 1 to " + MAX_GOOGLE_ADS_ROWS + " Google Ads conversion rows per request.");
        if (input.clickIdType() == null || !Set.of("gclid", "gbraid", "wbraid").contains(input.clickIdType()))
            throw invalid("Choose GCLID, GBRAID, or WBRAID for these rows.");
        if (input.eventSource() == null
                || !Set.of("WEB", "APP", "IN_STORE", "PHONE", "MESSAGE", "OTHER")
                        .contains(input.eventSource()))
            throw invalid("Choose a supported Google conversion event source.");
        Goal goal = goal(siteId, input.goalId(), true);
        List<NormalizedRow> normalized = normalizeRows(siteId, input.rows());
        Map<String, RowInput> rawRows = new HashMap<>();
        for (RowInput row : input.rows()) {
            String key = TrackingIdentityHasher.hash(
                    siteId, "offline-conversion:" + row.conversionId().trim());
            rawRows.put(key, row);
        }
        ensureRowsMatchImportedConversions(siteId, input.goalId(), normalized);

        List<Map<String, Object>> events = new ArrayList<>(normalized.size());
        for (NormalizedRow row : normalized) {
            RowInput raw = rawRows.get(row.conversionKeyHash());
            Map<String, Object> adIdentifiers = Map.of(input.clickIdType(), field(raw.clickId(), 2_048, "click_id", 0));
            Map<String, Object> event = new LinkedHashMap<>();
            event.put(
                    "transactionId",
                    TrackingIdentityHasher.hash(
                            siteId,
                            "google-ads-transaction:" + raw.conversionId().trim()));
            event.put("eventTimestamp", row.convertedAt().toString());
            event.put("eventSource", input.eventSource());
            event.put("adIdentifiers", adIdentifiers);
            event.put("conversionValue", goal.fixedValue());
            event.put("currency", destination.currencyCode());
            events.add(event);
        }

        Map<String, Object> payload = new LinkedHashMap<>();
        Map<String, Object> operatingAccount =
                Map.of("accountType", "GOOGLE_ADS", "accountId", destination.customerId());
        Map<String, Object> target = new LinkedHashMap<>();
        target.put("operatingAccount", operatingAccount);
        if (destination.loginCustomerId() != null)
            target.put("loginAccount", Map.of("accountType", "GOOGLE_ADS", "accountId", destination.loginCustomerId()));
        target.put("productDestinationId", destination.conversionActionId());
        payload.put("destinations", List.of(target));
        payload.put("events", events);
        GoogleAdsDataManagerGateway.Result result = googleAds.ingest(payload, validateOnly);
        return new GoogleAdsTransferResult(validateOnly, events.size(), result.requestId(), result.fieldWarnings());
    }

    private GoogleAdsDestination googleAdsDestination(UUID siteId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select customer_id,login_customer_id,conversion_action_id,currency_code "
                                + "from analytics_google_ads_conversion_config where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next())
                    throw new ControlPlaneException(
                            409,
                            "GOOGLE_ADS_CONFIG_REQUIRED",
                            "Save a Google Ads account, conversion action, and currency first.");
                return new GoogleAdsDestination(row.getString(1), row.getString(2), row.getString(3), row.getString(4));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not load Google Ads conversion destination", error);
        }
    }

    private void ensureRowsMatchImportedConversions(UUID siteId, UUID goalId, List<NormalizedRow> rows) {
        String placeholders = String.join(",", Collections.nCopies(rows.size(), "?"));
        String sql = "select conversion_key_hash,ad_click_platform,ad_click_id_hash,converted_at "
                + "from analytics_offline_conversion where site_id=? and goal_id=? and conversion_key_hash in ("
                + placeholders + ")";
        Map<String, StoredConversion> stored = new HashMap<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            for (int i = 0; i < rows.size(); i++)
                statement.setString(i + 3, rows.get(i).conversionKeyHash());
            try (ResultSet result = statement.executeQuery()) {
                while (result.next())
                    stored.put(
                            result.getString(1),
                            new StoredConversion(
                                    result.getString(2),
                                    result.getString(3),
                                    result.getTimestamp(4).toInstant()));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not verify imported Google Ads conversions", error);
        }
        for (NormalizedRow row : rows) {
            StoredConversion existing = stored.get(row.conversionKeyHash());
            if (existing == null
                    || !"google_ads".equals(existing.platform())
                    || !existing.clickIdHash().equals(row.clickIdHash())
                    || !existing.convertedAt().equals(row.convertedAt()))
                throw new ControlPlaneException(
                        409,
                        "GOOGLE_ADS_EXPORT_ROW_NOT_IMPORTED",
                        "Every exported row must exactly match a Google Ads conversion already imported for this site and goal.");
        }
    }

    private static String customerId(String value, String label) {
        String normalized = value == null ? "" : value.replaceAll("[-\\s]", "");
        if (!normalized.matches("[0-9]{10}")) throw invalid(label + " must contain exactly 10 digits.");
        return normalized;
    }

    public ImportHistory imports(UUID siteId) {
        Site site = readableSite(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        List<ImportBatch> batches = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select i.id,i.goal_id,g.name,i.row_count,i.imported_at from analytics_offline_conversion_import i "
                                + "join goal_definition g on g.id=i.goal_id and g.site_id=i.site_id "
                                + "where i.site_id=? order by i.imported_at desc,i.id desc limit 30")) {
            statement.setObject(1, siteId);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next())
                    batches.add(new ImportBatch(
                            rows.getObject(1, UUID.class),
                            rows.getObject(2, UUID.class),
                            rows.getString(3),
                            rows.getInt(4),
                            rows.getTimestamp(5).toInstant()));
            }
            return new ImportHistory(canManage, site.timezone, List.copyOf(batches));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not list offline conversion imports", error);
        }
    }

    @Transactional
    public ImportResult importRows(UUID siteId, UUID goalId, List<RowInput> inputRows) {
        Site site = writableSite(siteId);
        Goal goal = goal(siteId, goalId, true);
        List<NormalizedRow> rows = normalizeRows(siteId, inputRows);
        String contentHash = contentHash(siteId, goalId, rows);
        UUID importId = UuidV7.next();
        try (Connection connection = dataSource.getConnection()) {
            try (PreparedStatement insert = connection.prepareStatement(
                    "insert into analytics_offline_conversion_import(id,site_id,goal_id,file_hash,row_count,actor_user_id) "
                            + "values(?,?,?,?,?,?) on conflict(site_id,goal_id,file_hash) do nothing")) {
                insert.setObject(1, importId);
                insert.setObject(2, siteId);
                insert.setObject(3, goalId);
                insert.setString(4, contentHash);
                insert.setInt(5, rows.size());
                insert.setObject(6, access.userId());
                if (insert.executeUpdate() == 0) {
                    try (PreparedStatement existing = connection.prepareStatement(
                            "select id,row_count,imported_at from analytics_offline_conversion_import "
                                    + "where site_id=? and goal_id=? and file_hash=?")) {
                        existing.setObject(1, siteId);
                        existing.setObject(2, goalId);
                        existing.setString(3, contentHash);
                        try (ResultSet result = existing.executeQuery()) {
                            if (!result.next()) throw new IllegalStateException("Duplicate import disappeared");
                            return new ImportResult(
                                    result.getObject(1, UUID.class),
                                    result.getInt(2),
                                    true,
                                    result.getTimestamp(3).toInstant());
                        }
                    }
                }
            }
            rejectPreviouslyImportedConversions(connection, siteId, rows);
            try (PreparedStatement insert = connection.prepareStatement(
                    "insert into analytics_offline_conversion(id,import_id,site_id,goal_id,conversion_key_hash,"
                            + "ad_click_platform,ad_click_id_hash,converted_at) values(?,?,?,?,?,?,?,?)")) {
                for (NormalizedRow row : rows) {
                    insert.setObject(1, UuidV7.next());
                    insert.setObject(2, importId);
                    insert.setObject(3, siteId);
                    insert.setObject(4, goalId);
                    insert.setString(5, row.conversionKeyHash());
                    insert.setString(6, row.platform());
                    insert.setString(7, row.clickIdHash());
                    insert.setTimestamp(8, Timestamp.from(row.convertedAt()));
                    insert.addBatch();
                }
                insert.executeBatch();
            }
            return new ImportResult(importId, rows.size(), false, Instant.now());
        } catch (SQLException error) {
            if ("23505".equals(error.getSQLState()))
                throw new ControlPlaneException(
                        409, "OFFLINE_CONVERSION_DUPLICATE", "One or more conversion IDs were imported previously");
            throw new IllegalStateException("Could not import offline conversions", error);
        }
    }

    public Report report(
            UUID siteId,
            AnalyticsQueryService.Range range,
            UUID segmentId,
            UUID goalId,
            String requestedModel,
            int lookbackDays) {
        String model = requestedModel == null ? "last_touch" : requestedModel;
        if (!MODELS.contains(model) || !LOOKBACK_DAYS.contains(lookbackDays))
            throw new ControlPlaneException(
                    400, "INVALID_ATTRIBUTION_QUERY", "Choose a supported attribution model and lookback window");
        Site site = readableSite(siteId);
        SegmentService.SessionFilter filter = segments.sessionFilter(siteId, segmentId);
        String goalClause = goalId == null ? "" : "and oc.goal_id=? ";
        String weight = AttributionQueryService.conversionWeightExpression(model);
        String sql = "with imported as ("
                + "select oc.id,oc.goal_id,g.name goal_name,g.fixed_value,oc.ad_click_platform,oc.ad_click_id_hash,oc.converted_at "
                + "from analytics_offline_conversion oc join goal_definition g on g.id=oc.goal_id and g.site_id=oc.site_id "
                + "where oc.site_id=? and g.enabled and (oc.converted_at at time zone ?)::date between ? and ? "
                + goalClause + "), ranked_matches as ("
                + "select i.*,s.id matched_session_id,s.identity_key,s.started_at matched_at,"
                + "row_number() over(partition by i.id order by s.started_at desc,s.id desc) match_rank "
                + "from imported i left join analytics_session s on s.site_id=? "
                + "and s.ad_click_platform=i.ad_click_platform and s.ad_click_id_hash=i.ad_click_id_hash "
                + "and s.started_at<=i.converted_at and s.started_at>=i.converted_at-(? * interval '1 day') "
                + "and (" + filter.expression() + ")), matches as ("
                + "select * from ranked_matches where match_rank=1), classified_sessions as ("
                + "select classified.*,case when classified.channel='campaign' then nullif(classified.initial_utm_source,'') "
                + "when classified.channel='direct' then null else nullif(classified.initial_referrer_host,'') end source "
                + "from (select s.id,s.site_id,s.identity_key,s.started_at,s.initial_referrer_host,s.initial_utm_source,"
                + "s.initial_utm_medium,s.initial_utm_campaign," + AcquisitionClassifier.channelSql("s")
                + " channel from analytics_session s where s.site_id=?) classified), touches as ("
                + "select m.id conversion_id,m.goal_id,m.goal_name,m.fixed_value,m.ad_click_platform platform,"
                + "m.converted_at conversion_at,t.started_at touch_at,t.channel,t.source,t.initial_utm_medium medium,"
                + "t.initial_utm_campaign campaign,row_number() over(partition by m.id order by t.started_at,t.id) touch_number,"
                + "count(*) over(partition by m.id) touch_count from matches m join classified_sessions t "
                + "on m.identity_key=t.identity_key and t.started_at<=m.converted_at "
                + "and t.started_at>=m.converted_at-(? * interval '1 day') where m.matched_session_id is not null), "
                + "raw_weights as (select *," + weight + " raw_weight from touches), weighted as ("
                + "select conversion_id,goal_id,goal_name,fixed_value,platform,channel,source,medium,campaign,"
                + "raw_weight/nullif(sum(raw_weight) over(partition by conversion_id),0) credit "
                + "from raw_weights where raw_weight>0), report_rows as ("
                + "select goal_id,goal_name,platform,channel,source,medium,campaign,sum(credit) attributed_conversions,"
                + "sum(credit*fixed_value) attributed_value from weighted "
                + "group by goal_id,goal_name,platform,channel,source,medium,campaign), stats as ("
                + "select count(*) total_imported,count(matched_session_id) matched from matches) "
                + "select stats.total_imported,stats.matched,r.goal_id,r.goal_name,r.platform,r.channel,r.source,r.medium,r.campaign,"
                + "r.attributed_conversions,r.attributed_value from stats left join report_rows r on true "
                + "order by r.attributed_conversions desc nulls last,r.goal_name,r.platform,r.channel,r.source nulls last";

        List<Row> rows = new ArrayList<>();
        long imported = 0;
        long matched = 0;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            int index = 1;
            statement.setObject(index++, siteId);
            statement.setString(index++, site.timezone);
            statement.setObject(index++, range.from());
            statement.setObject(index++, range.to());
            if (goalId != null) statement.setObject(index++, goalId);
            statement.setObject(index++, siteId);
            statement.setInt(index++, lookbackDays);
            for (Object value : filter.values()) statement.setObject(index++, value);
            statement.setObject(index++, siteId);
            statement.setInt(index, lookbackDays);
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    imported = result.getLong(1);
                    matched = result.getLong(2);
                    UUID rowGoalId = result.getObject(3, UUID.class);
                    if (rowGoalId == null) continue;
                    rows.add(new Row(
                            rowGoalId,
                            result.getString(4),
                            result.getString(5),
                            result.getString(6),
                            result.getString(7),
                            result.getString(8),
                            result.getString(9),
                            result.getBigDecimal(10),
                            result.getBigDecimal(11)));
                }
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not query offline conversion attribution", error);
        }
        var attributedConversions = rows.stream()
                .map(Row::attributedConversions)
                .reduce(java.math.BigDecimal.ZERO, java.math.BigDecimal::add);
        var attributedValue =
                rows.stream().map(Row::attributedValue).reduce(java.math.BigDecimal.ZERO, java.math.BigDecimal::add);
        return new Report(
                range.from(),
                range.to(),
                goalId == null ? null : goal(siteId, goalId, false).name(),
                model,
                lookbackDays,
                imported,
                matched,
                Math.max(0, imported - matched),
                attributedConversions,
                attributedValue,
                List.copyOf(rows));
    }

    private static void rejectPreviouslyImportedConversions(
            Connection connection, UUID siteId, List<NormalizedRow> rows) throws SQLException {
        String placeholders = String.join(",", Collections.nCopies(rows.size(), "?"));
        try (PreparedStatement statement = connection.prepareStatement(
                "select 1 from analytics_offline_conversion where site_id=? and conversion_key_hash in (" + placeholders
                        + ") limit 1")) {
            statement.setObject(1, siteId);
            for (int i = 0; i < rows.size(); i++)
                statement.setString(i + 2, rows.get(i).conversionKeyHash());
            try (ResultSet result = statement.executeQuery()) {
                if (result.next())
                    throw new ControlPlaneException(
                            409, "OFFLINE_CONVERSION_DUPLICATE", "One or more conversion IDs were imported previously");
            }
        }
    }

    private List<NormalizedRow> normalizeRows(UUID siteId, List<RowInput> values) {
        if (values == null || values.isEmpty() || values.size() > MAX_IMPORT_ROWS)
            throw invalid("Choose a CSV with 1 to " + MAX_IMPORT_ROWS + " offline conversion rows.");
        List<NormalizedRow> normalized = new ArrayList<>();
        Set<String> conversionKeys = new HashSet<>();
        long characters = 0;
        for (int i = 0; i < values.size(); i++) {
            RowInput row = values.get(i);
            int rowNumber = i + 2;
            if (row == null) throw invalid("Row " + rowNumber + " is empty.");
            characters += length(row.conversionId())
                    + length(row.platform())
                    + length(row.clickId())
                    + length(row.convertedAt())
                    + 24;
            if (characters > MAX_IMPORT_CHARACTERS)
                throw invalid("Offline conversion imports must be 2 MiB or smaller.");
            String conversionId = field(row.conversionId(), 256, "conversion_id", rowNumber);
            String platform =
                    row.platform() == null ? "" : row.platform().trim().toLowerCase(Locale.ROOT);
            if (!PLATFORMS.contains(platform))
                throw invalid("Row " + rowNumber + ": choose a platform with a supported ad click ID.");
            String clickId = field(row.clickId(), 2048, "click_id", rowNumber);
            String timestampText = field(row.convertedAt(), 64, "converted_at", rowNumber);
            Instant convertedAt;
            try {
                convertedAt = OffsetDateTime.parse(timestampText).toInstant();
            } catch (DateTimeParseException error) {
                throw invalid(
                        "Row " + rowNumber + ": converted_at must be an ISO-8601 date-time with a timezone offset.");
            }
            String conversionHash = TrackingIdentityHasher.hash(siteId, "offline-conversion:" + conversionId);
            if (!conversionKeys.add(conversionHash))
                throw invalid("Row " + rowNumber + ": conversion_id appears more than once.");
            normalized.add(new NormalizedRow(
                    platform, convertedAt, conversionHash, TrackingIdentityHasher.hash(siteId, "ad-click:" + clickId)));
        }
        normalized.sort(Comparator.comparing(NormalizedRow::convertedAt)
                .thenComparing(NormalizedRow::platform)
                .thenComparing(NormalizedRow::clickIdHash)
                .thenComparing(NormalizedRow::conversionKeyHash));
        return List.copyOf(normalized);
    }

    private static String contentHash(UUID siteId, UUID goalId, List<NormalizedRow> rows) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            digest.update(siteId.toString().getBytes(StandardCharsets.UTF_8));
            digest.update((byte) 0x1f);
            digest.update(goalId.toString().getBytes(StandardCharsets.UTF_8));
            digest.update((byte) 0x0a);
            for (NormalizedRow row : rows) {
                for (String value : List.of(
                        row.platform(), row.convertedAt().toString(), row.conversionKeyHash(), row.clickIdHash())) {
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

    private Goal goal(UUID siteId, UUID goalId, boolean requireEnabled) {
        if (goalId == null) throw invalid("Choose a configured goal for these offline conversions.");
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select name,fixed_value,enabled from goal_definition where site_id=? and id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next() || (requireEnabled && !row.getBoolean(3)))
                    throw invalid("Choose an enabled goal belonging to this site.");
                return new Goal(row.getString(1), row.getBigDecimal(2));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not validate offline conversion goal", error);
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

    private static String field(String value, int maximum, String label, int row) {
        if (value != null && value.chars().anyMatch(Character::isISOControl))
            throw invalid("Row " + row + ": " + label + " must not contain control characters.");
        String normalized = value == null ? "" : value.trim().replaceAll("\\s+", " ");
        if (normalized.isBlank() || normalized.length() > maximum)
            throw invalid("Row " + row + ": " + label + " is required and must be at most " + maximum + " characters.");
        return normalized;
    }

    private static int length(String value) {
        return value == null ? 0 : value.length();
    }

    private static ControlPlaneException invalid(String message) {
        return new ControlPlaneException(400, "OFFLINE_CONVERSION_IMPORT_INVALID", message);
    }

    public record GoogleAdsConfigInput(
            String customerId, String loginCustomerId, String conversionActionId, String currencyCode) {}

    public record GoogleAdsConfigView(
            boolean canManage,
            boolean configured,
            String customerId,
            String loginCustomerId,
            String conversionActionId,
            String currencyCode,
            Instant updatedAt) {}

    public record GoogleAdsTransferInput(UUID goalId, String clickIdType, String eventSource, List<RowInput> rows) {}

    public record GoogleAdsTransferResult(
            boolean validatedOnly, int rowsProcessed, String requestId, List<Map<String, Object>> fieldWarnings) {}

    public record RowInput(String conversionId, String platform, String clickId, String convertedAt) {}

    public record ImportBatch(UUID id, UUID goalId, String goalName, int rowCount, Instant importedAt) {}

    public record ImportHistory(boolean canManage, String timezone, List<ImportBatch> imports) {}

    public record ImportResult(UUID id, int rowsImported, boolean alreadyImported, Instant importedAt) {}

    public record Report(
            java.time.LocalDate from,
            java.time.LocalDate to,
            String selectedGoalName,
            String model,
            int lookbackDays,
            long totalImported,
            long matchedConversions,
            long unmatchedConversions,
            java.math.BigDecimal attributedConversions,
            java.math.BigDecimal attributedValue,
            List<Row> rows) {}

    public record Row(
            UUID goalId,
            String goalName,
            String platform,
            String channel,
            String source,
            String medium,
            String campaign,
            java.math.BigDecimal attributedConversions,
            java.math.BigDecimal attributedValue) {}

    private record Goal(String name, java.math.BigDecimal fixedValue) {}

    private record GoogleAdsDestination(
            String customerId, String loginCustomerId, String conversionActionId, String currencyCode) {}

    private record StoredConversion(String platform, String clickIdHash, Instant convertedAt) {}

    private record NormalizedRow(String platform, Instant convertedAt, String conversionKeyHash, String clickIdHash) {}
}
