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
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.Currency;
import javax.sql.DataSource;

/** Privacy-preserving click-id joins for operator-imported, goal-scoped offline conversions. */
@ApplicationScoped
public class OfflineConversionService {
    private static final int MAX_IMPORT_ROWS = 5_000;
    private static final int MAX_GOOGLE_ADS_ROWS = 2_000;
    private static final int MAX_META_ADS_ROWS = 1_000;
    private static final int MAX_LINKEDIN_ADS_ROWS = 5_000;
    private static final int MAX_X_ADS_ROWS = 2_000;
    private static final int MAX_IMPORT_CHARACTERS = 2 * 1024 * 1024;
    private static final Set<String> PLATFORMS =
            Set.of("google_ads", "microsoft_ads", "meta_ads", "tiktok_ads", "linkedin_ads", "x_ads");
    private static final Set<String> MODELS =
            Set.of("first_touch", "last_touch", "linear", "position_based", "time_decay");
    private static final Set<Integer> LOOKBACK_DAYS = Set.of(7, 30, 90);
    private static final Set<String> META_ACTION_SOURCES = Set.of(
            "website",
            "app",
            "business_messaging",
            "chat",
            "email",
            "other",
            "phone_call",
            "physical_store",
            "system_generated");

    private final DataSource dataSource;
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final SegmentService segments;
    private final GoogleAdsDataManagerGateway googleAds;
    private final MicrosoftAdsCapiGateway microsoftAds;
    private final MetaAdsCapiGateway metaAds;
    private final LinkedInConversionsGateway linkedInAds;
    private final XAdsConversionsGateway xAds;
    private final SecretEncryptionService encryption;

    @Inject
    public OfflineConversionService(
            DataSource dataSource,
            SiteService sites,
            WorkspaceAccess access,
            SegmentService segments,
            GoogleAdsDataManagerGateway googleAds,
            MicrosoftAdsCapiGateway microsoftAds,
            MetaAdsCapiGateway metaAds,
            LinkedInConversionsGateway linkedInAds,
            XAdsConversionsGateway xAds,
            SecretEncryptionService encryption) {
        this.dataSource = dataSource;
        this.sites = sites;
        this.access = access;
        this.segments = segments;
        this.googleAds = googleAds;
        this.microsoftAds = microsoftAds;
        this.metaAds = metaAds;
        this.linkedInAds = linkedInAds;
        this.xAds = xAds;
        this.encryption = encryption;
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
        ensureRowsMatchImportedConversions(siteId, input.goalId(), normalized, "google_ads");

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

    public MicrosoftAdsConfigView microsoftAdsConfig(UUID siteId) {
        Site site = readableSite(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        String tagId = null;
        String currencyCode = null;
        boolean configured = false;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select tag_id,currency_code from analytics_microsoft_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet row = statement.executeQuery()) {
                if (row.next()) {
                    tagId = row.getString(1);
                    currencyCode = row.getString(2);
                    configured = true;
                }
            }
            List<MicrosoftAdsGoalMappingView> mappings = new ArrayList<>();
            try (PreparedStatement mappingStatement = connection.prepareStatement(
                    "select m.goal_id,g.name,m.event_name from analytics_microsoft_ads_goal_mapping m "
                            + "join goal_definition g on g.id=m.goal_id and g.site_id=m.site_id "
                            + "where m.site_id=? and g.enabled order by g.name,m.goal_id")) {
                mappingStatement.setObject(1, siteId);
                try (ResultSet rows = mappingStatement.executeQuery()) {
                    while (rows.next()) {
                        mappings.add(new MicrosoftAdsGoalMappingView(
                                rows.getObject(1, UUID.class), rows.getString(2), rows.getString(3)));
                    }
                }
            }
            return new MicrosoftAdsConfigView(
                    canManage, configured, configured, tagId, currencyCode, List.copyOf(mappings));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read Microsoft Ads CAPI configuration", error);
        }
    }

    @Transactional
    public MicrosoftAdsConfigView saveMicrosoftAdsConfig(UUID siteId, MicrosoftAdsConfigInput input) {
        writableSite(siteId);
        if (input == null) throw invalid("Enter a Microsoft Ads UET tag ID and currency.");
        String tagId = input.tagId() == null ? "" : input.tagId().strip();
        if (!tagId.matches("[0-9]{1,32}")) throw invalid("Microsoft Ads UET tag ID must contain 1 to 32 digits.");
        String currencyCode =
                input.currencyCode() == null ? "" : input.currencyCode().strip().toUpperCase(Locale.ROOT);
        try {
            Currency.getInstance(currencyCode);
        } catch (IllegalArgumentException error) {
            throw invalid("Choose a valid three-letter ISO currency code.");
        }
        ExistingMicrosoftAdsConfig existing = existingMicrosoftAdsConfig(siteId);
        byte[] encryptedToken;
        if (input.apiToken() == null || input.apiToken().isBlank()) {
            if (existing == null) {
                throw new ControlPlaneException(
                        400,
                        "MICROSOFT_ADS_TOKEN_REQUIRED",
                        "Enter the Conversions API token for the first connection.");
            }
            encryptedToken = existing.tokenCiphertext();
        } else {
            String token = input.apiToken().strip();
            if (token.length() > 8_192) throw invalid("The Microsoft Ads Conversions API token is too long.");
            encryptedToken = encryption.encrypt(token);
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_microsoft_ads_capi_config(site_id,tag_id,currency_code,api_token_ciphertext,updated_by,updated_at) "
                                + "values(?,?,?,?,?,now()) on conflict(site_id) do update set tag_id=excluded.tag_id,"
                                + "currency_code=excluded.currency_code,api_token_ciphertext=excluded.api_token_ciphertext,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setString(2, tagId);
            statement.setString(3, currencyCode);
            statement.setBytes(4, encryptedToken);
            statement.setObject(5, access.userId());
            statement.executeUpdate();
            return microsoftAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save Microsoft Ads CAPI configuration", error);
        }
    }

    @Transactional
    public MicrosoftAdsConfigView mapMicrosoftAdsGoal(UUID siteId, UUID goalId, String eventNameValue) {
        writableSite(siteId);
        goal(siteId, goalId, true);
        String eventName = eventNameValue == null ? "" : eventNameValue.strip();
        if (eventName.isBlank() || eventName.length() > 128 || eventName.chars().anyMatch(Character::isISOControl)) {
            throw invalid("Microsoft Ads event name is required and must be at most 128 characters.");
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_microsoft_ads_goal_mapping(site_id,goal_id,event_name,updated_by,updated_at) "
                                + "values(?,?,?,?,now()) on conflict(site_id,goal_id) do update set event_name=excluded.event_name,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            statement.setString(3, eventName);
            statement.setObject(4, access.userId());
            statement.executeUpdate();
            return microsoftAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save Microsoft Ads goal mapping", error);
        }
    }

    @Transactional
    public MicrosoftAdsConfigView removeMicrosoftAdsGoalMapping(UUID siteId, UUID goalId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "delete from analytics_microsoft_ads_goal_mapping where site_id=? and goal_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            statement.executeUpdate();
            return microsoftAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not remove Microsoft Ads goal mapping", error);
        }
    }

    @Transactional
    public MicrosoftAdsConfigView removeMicrosoftAdsConfig(UUID siteId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "delete from analytics_microsoft_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            statement.executeUpdate();
            return microsoftAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not remove Microsoft Ads CAPI configuration", error);
        }
    }

    public MicrosoftAdsTransferResult transferToMicrosoftAds(UUID siteId, MicrosoftAdsTransferInput input) {
        writableSite(siteId);
        if (input == null
                || input.goalId() == null
                || input.rows() == null
                || input.rows().isEmpty()
                || input.rows().size() > 1_000) {
            throw invalid("Choose 1 to 1,000 Microsoft Ads conversion rows per send.");
        }
        if (!input.consentConfirmed()) {
            throw new ControlPlaneException(
                    400,
                    "MICROSOFT_ADS_CONSENT_CONFIRMATION_REQUIRED",
                    "Confirm that ad-storage and conversion-measurement consent was granted for every exported row.");
        }
        MicrosoftAdsDestination destination = microsoftAdsDestination(siteId);
        Goal goal = goal(siteId, input.goalId(), true);
        String eventName = microsoftAdsEventName(siteId, input.goalId());
        List<NormalizedRow> normalized = normalizeRows(siteId, input.rows());
        ensureRowsMatchImportedConversions(siteId, input.goalId(), normalized, "microsoft_ads");
        Instant now = Instant.now();
        Map<String, RowInput> rawRows = new HashMap<>();
        for (RowInput row : input.rows()) {
            String key = TrackingIdentityHasher.hash(
                    siteId, "offline-conversion:" + row.conversionId().trim());
            rawRows.put(key, row);
        }
        List<Map<String, Object>> events = new ArrayList<>(normalized.size());
        for (NormalizedRow row : normalized) {
            RowInput raw = rawRows.get(row.conversionKeyHash());
            if (!"microsoft_ads".equals(row.platform())) {
                throw invalid("Every row must use platform microsoft_ads.");
            }
            String clickId = field(raw.clickId(), 2_048, "MSCLKID", 0);
            if (!clickId.matches("(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")) {
                throw invalid("Every Microsoft Ads click ID must be a valid MSCLKID UUID.");
            }
            if (row.convertedAt().isBefore(now.minus(Duration.ofDays(7)))
                    || row.convertedAt().isAfter(now.plus(Duration.ofMinutes(5)))) {
                throw invalid("Microsoft Ads accepts conversion event times only within the last 7 days.");
            }
            Map<String, Object> customData = new LinkedHashMap<>();
            customData.put("value", goal.fixedValue().doubleValue());
            customData.put("currency", destination.currencyCode());
            customData.put(
                    "transactionId",
                    TrackingIdentityHasher.hash(
                            siteId,
                            "microsoft-ads-transaction:" + raw.conversionId().trim()));
            Map<String, Object> event = new LinkedHashMap<>();
            event.put("eventType", "custom");
            event.put(
                    "eventId",
                    TrackingIdentityHasher.hash(
                            siteId, "microsoft-ads-event:" + raw.conversionId().trim()));
            event.put("eventName", eventName);
            event.put("eventTime", row.convertedAt().getEpochSecond());
            event.put("adStorageConsent", "G");
            event.put("userData", Map.of("msclkid", clickId));
            event.put("customData", customData);
            events.add(event);
        }
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("data", events);
        payload.put("continueOnValidationError", false);
        payload.put("dataProvider", "SeeRay Lens");
        MicrosoftAdsCapiGateway.Result result =
                microsoftAds.send(destination.tagId(), encryption.decrypt(destination.tokenCiphertext()), payload);
        return new MicrosoftAdsTransferResult(events.size(), result.eventsReceived(), result.validationWarnings());
    }

    public MetaAdsConfigView metaAdsConfig(UUID siteId) {
        Site site = readableSite(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        String datasetId = null;
        String currencyCode = null;
        boolean configured = false;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select dataset_id,currency_code from analytics_meta_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet row = statement.executeQuery()) {
                if (row.next()) {
                    datasetId = row.getString(1);
                    currencyCode = row.getString(2);
                    configured = true;
                }
            }
            List<MetaAdsGoalMappingView> mappings = new ArrayList<>();
            try (PreparedStatement mappingStatement = connection.prepareStatement(
                    "select m.goal_id,g.name,m.event_name from analytics_meta_ads_goal_mapping m "
                            + "join goal_definition g on g.id=m.goal_id and g.site_id=m.site_id "
                            + "where m.site_id=? and g.enabled order by g.name,m.goal_id")) {
                mappingStatement.setObject(1, siteId);
                try (ResultSet rows = mappingStatement.executeQuery()) {
                    while (rows.next()) {
                        mappings.add(new MetaAdsGoalMappingView(
                                rows.getObject(1, UUID.class), rows.getString(2), rows.getString(3)));
                    }
                }
            }
            return new MetaAdsConfigView(
                    canManage, configured, configured, datasetId, currencyCode, List.copyOf(mappings));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read Meta Ads CAPI configuration", error);
        }
    }

    @Transactional
    public MetaAdsConfigView saveMetaAdsConfig(UUID siteId, MetaAdsConfigInput input) {
        writableSite(siteId);
        if (input == null) throw invalid("Enter a Meta dataset/pixel ID and currency.");
        String datasetId = input.datasetId() == null ? "" : input.datasetId().strip();
        if (!datasetId.matches("[0-9]{1,32}")) throw invalid("Meta dataset/pixel ID must contain 1 to 32 digits.");
        String currencyCode =
                input.currencyCode() == null ? "" : input.currencyCode().strip().toUpperCase(Locale.ROOT);
        try {
            Currency.getInstance(currencyCode);
        } catch (IllegalArgumentException error) {
            throw invalid("Choose a valid three-letter ISO currency code.");
        }
        ExistingMetaAdsConfig existing = existingMetaAdsConfig(siteId);
        byte[] encryptedToken;
        if (input.apiToken() == null || input.apiToken().isBlank()) {
            if (existing == null) {
                throw new ControlPlaneException(
                        400,
                        "META_ADS_TOKEN_REQUIRED",
                        "Enter the Meta Conversions API access token for the first connection.");
            }
            encryptedToken = existing.tokenCiphertext();
        } else {
            String token = input.apiToken().strip();
            if (token.length() > 8_192) throw invalid("The Meta Conversions API token is too long.");
            encryptedToken = encryption.encrypt(token);
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_meta_ads_capi_config(site_id,dataset_id,currency_code,api_token_ciphertext,updated_by,updated_at) "
                                + "values(?,?,?,?,?,now()) on conflict(site_id) do update set dataset_id=excluded.dataset_id,"
                                + "currency_code=excluded.currency_code,api_token_ciphertext=excluded.api_token_ciphertext,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setString(2, datasetId);
            statement.setString(3, currencyCode);
            statement.setBytes(4, encryptedToken);
            statement.setObject(5, access.userId());
            statement.executeUpdate();
            return metaAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save Meta Ads CAPI configuration", error);
        }
    }

    @Transactional
    public MetaAdsConfigView mapMetaAdsGoal(UUID siteId, UUID goalId, String eventNameValue) {
        writableSite(siteId);
        goal(siteId, goalId, true);
        String eventName = eventNameValue == null ? "" : eventNameValue.strip();
        if (eventName.isBlank() || eventName.length() > 128 || eventName.chars().anyMatch(Character::isISOControl)) {
            throw invalid("Meta event name is required and must be at most 128 characters.");
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_meta_ads_goal_mapping(site_id,goal_id,event_name,updated_by,updated_at) "
                                + "values(?,?,?,?,now()) on conflict(site_id,goal_id) do update set event_name=excluded.event_name,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            statement.setString(3, eventName);
            statement.setObject(4, access.userId());
            statement.executeUpdate();
            return metaAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save Meta Ads goal mapping", error);
        }
    }

    @Transactional
    public MetaAdsConfigView removeMetaAdsGoalMapping(UUID siteId, UUID goalId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "delete from analytics_meta_ads_goal_mapping where site_id=? and goal_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            statement.executeUpdate();
            return metaAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not remove Meta Ads goal mapping", error);
        }
    }

    @Transactional
    public MetaAdsConfigView removeMetaAdsConfig(UUID siteId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement =
                        connection.prepareStatement("delete from analytics_meta_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            statement.executeUpdate();
            return metaAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not remove Meta Ads CAPI configuration", error);
        }
    }

    public MetaAdsTransferResult transferToMetaAds(UUID siteId, MetaAdsTransferInput input) {
        writableSite(siteId);
        if (input == null
                || input.goalId() == null
                || input.rows() == null
                || input.rows().isEmpty()
                || input.rows().size() > MAX_META_ADS_ROWS) {
            throw invalid("Choose 1 to 1,000 Meta Ads conversion rows per send.");
        }
        if (!input.consentConfirmed()) {
            throw new ControlPlaneException(
                    400,
                    "META_ADS_CONSENT_CONFIRMATION_REQUIRED",
                    "Confirm that every exported row has consent for ad-storage and conversion measurement.");
        }
        MetaAdsDestination destination = metaAdsDestination(siteId);
        Goal goal = goal(siteId, input.goalId(), true);
        String eventName = metaAdsEventName(siteId, input.goalId());
        String actionSource =
                input.actionSource() == null ? "" : input.actionSource().strip().toLowerCase(Locale.ROOT);
        if (!META_ACTION_SOURCES.contains(actionSource)) {
            throw invalid("Choose a supported Meta Conversions API action source.");
        }
        List<NormalizedRow> normalized = normalizeRows(siteId, input.rows());
        ensureRowsMatchImportedConversions(siteId, input.goalId(), normalized, "meta_ads");
        Instant now = Instant.now();
        Map<String, RowInput> rawRows = new HashMap<>();
        for (RowInput row : input.rows()) {
            String key = TrackingIdentityHasher.hash(
                    siteId, "offline-conversion:" + row.conversionId().trim());
            rawRows.put(key, row);
        }
        Map<String, NavigableSet<Instant>> clickVisits = metaClickVisits(siteId, normalized);
        List<Map<String, Object>> events = new ArrayList<>(normalized.size());
        for (NormalizedRow row : normalized) {
            RowInput raw = rawRows.get(row.conversionKeyHash());
            if (!"meta_ads".equals(row.platform())) throw invalid("Every row must use platform meta_ads.");
            String clickId = field(raw.clickId(), 2_048, "FBCLID", 0);
            if (!clickId.matches("[A-Za-z0-9._-]{1,2048}"))
                throw invalid("Every Meta click ID must be a valid FBCLID.");
            if (row.convertedAt().isBefore(now.minus(Duration.ofDays(7)))
                    || row.convertedAt().isAfter(now.plus(Duration.ofMinutes(5)))) {
                throw invalid("Meta Conversions API accepts event times only within the last 7 days.");
            }
            NavigableSet<Instant> visits = clickVisits.get(row.clickIdHash());
            Instant clickAt = visits == null ? null : visits.floor(row.convertedAt());
            if (clickAt == null || clickAt.isBefore(row.convertedAt().minus(Duration.ofDays(7)))) {
                throw new ControlPlaneException(
                        409,
                        "META_ADS_MATCHED_VISIT_REQUIRED",
                        "Every row must match a tracked Meta ad click from this site within 7 days before conversion.");
            }
            Map<String, Object> userData = Map.of("fbc", "fb.1." + clickAt.toEpochMilli() + "." + clickId);
            Map<String, Object> customData = Map.of(
                    "value", goal.fixedValue().doubleValue(),
                    "currency", destination.currencyCode());
            Map<String, Object> event = new LinkedHashMap<>();
            event.put("event_name", eventName);
            event.put("event_time", row.convertedAt().getEpochSecond());
            event.put(
                    "event_id",
                    TrackingIdentityHasher.hash(
                            siteId, "meta-ads-event:" + raw.conversionId().trim()));
            event.put("action_source", actionSource);
            event.put("user_data", userData);
            event.put("custom_data", customData);
            events.add(event);
        }
        Map<String, Object> payload = Map.of("data", events);
        MetaAdsCapiGateway.Result result =
                metaAds.send(destination.datasetId(), encryption.decrypt(destination.tokenCiphertext()), payload);
        return new MetaAdsTransferResult(events.size(), result.eventsReceived());
    }

    public LinkedInAdsConfigView linkedInAdsConfig(UUID siteId) {
        Site site = readableSite(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        String currencyCode = null;
        boolean configured = false;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select currency_code from analytics_linkedin_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet row = statement.executeQuery()) {
                if (row.next()) {
                    currencyCode = row.getString(1);
                    configured = true;
                }
            }
            List<LinkedInAdsGoalMappingView> mappings = new ArrayList<>();
            try (PreparedStatement mappingStatement = connection.prepareStatement(
                    "select m.goal_id,g.name,m.conversion_urn from analytics_linkedin_ads_goal_mapping m "
                            + "join goal_definition g on g.id=m.goal_id and g.site_id=m.site_id "
                            + "where m.site_id=? and g.enabled order by g.name,m.goal_id")) {
                mappingStatement.setObject(1, siteId);
                try (ResultSet rows = mappingStatement.executeQuery()) {
                    while (rows.next()) {
                        mappings.add(new LinkedInAdsGoalMappingView(
                                rows.getObject(1, UUID.class), rows.getString(2), rows.getString(3)));
                    }
                }
            }
            return new LinkedInAdsConfigView(canManage, configured, configured, currencyCode, List.copyOf(mappings));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read LinkedIn Conversions API configuration", error);
        }
    }

    @Transactional
    public LinkedInAdsConfigView saveLinkedInAdsConfig(UUID siteId, LinkedInAdsConfigInput input) {
        writableSite(siteId);
        if (input == null) throw invalid("Enter a currency and LinkedIn Conversions API access token.");
        String currencyCode =
                input.currencyCode() == null ? "" : input.currencyCode().strip().toUpperCase(Locale.ROOT);
        try {
            Currency.getInstance(currencyCode);
        } catch (IllegalArgumentException error) {
            throw invalid("Choose a valid three-letter ISO currency code.");
        }
        ExistingLinkedInAdsConfig existing = existingLinkedInAdsConfig(siteId);
        byte[] encryptedToken;
        if (input.apiToken() == null || input.apiToken().isBlank()) {
            if (existing == null) {
                throw new ControlPlaneException(
                        400,
                        "LINKEDIN_ADS_TOKEN_REQUIRED",
                        "Enter a LinkedIn Marketing API OAuth access token for the first connection.");
            }
            encryptedToken = existing.tokenCiphertext();
        } else {
            String token = input.apiToken().strip();
            if (token.length() > 8_192) throw invalid("The LinkedIn access token is too long.");
            encryptedToken = encryption.encrypt(token);
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_linkedin_ads_capi_config(site_id,currency_code,api_token_ciphertext,updated_by,updated_at) "
                                + "values(?,?,?,?,now()) on conflict(site_id) do update set currency_code=excluded.currency_code,"
                                + "api_token_ciphertext=excluded.api_token_ciphertext,updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setString(2, currencyCode);
            statement.setBytes(3, encryptedToken);
            statement.setObject(4, access.userId());
            statement.executeUpdate();
            return linkedInAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save LinkedIn Conversions API configuration", error);
        }
    }

    @Transactional
    public LinkedInAdsConfigView mapLinkedInAdsGoal(UUID siteId, UUID goalId, String conversionUrnValue) {
        writableSite(siteId);
        goal(siteId, goalId, true);
        String conversionUrn = conversionUrnValue == null ? "" : conversionUrnValue.strip();
        if (!conversionUrn.matches("urn:lla:llaPartnerConversion:[0-9]{1,32}")) {
            throw invalid("Enter a LinkedIn conversion rule URN such as urn:lla:llaPartnerConversion:123456.");
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_linkedin_ads_goal_mapping(site_id,goal_id,conversion_urn,updated_by,updated_at) "
                                + "values(?,?,?,?,now()) on conflict(site_id,goal_id) do update set conversion_urn=excluded.conversion_urn,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            statement.setString(3, conversionUrn);
            statement.setObject(4, access.userId());
            statement.executeUpdate();
            return linkedInAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save LinkedIn goal mapping", error);
        }
    }

    @Transactional
    public LinkedInAdsConfigView removeLinkedInAdsGoalMapping(UUID siteId, UUID goalId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "delete from analytics_linkedin_ads_goal_mapping where site_id=? and goal_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            statement.executeUpdate();
            return linkedInAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not remove LinkedIn goal mapping", error);
        }
    }

    @Transactional
    public LinkedInAdsConfigView removeLinkedInAdsConfig(UUID siteId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement =
                        connection.prepareStatement("delete from analytics_linkedin_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            statement.executeUpdate();
            return linkedInAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not remove LinkedIn Conversions API configuration", error);
        }
    }

    public LinkedInAdsTransferResult transferToLinkedInAds(UUID siteId, LinkedInAdsTransferInput input) {
        writableSite(siteId);
        if (input == null
                || input.goalId() == null
                || input.rows() == null
                || input.rows().isEmpty()
                || input.rows().size() > MAX_LINKEDIN_ADS_ROWS) {
            throw invalid("Choose 1 to 5,000 LinkedIn conversion rows per send.");
        }
        if (!input.consentConfirmed()) {
            throw new ControlPlaneException(
                    400,
                    "LINKEDIN_ADS_CONSENT_CONFIRMATION_REQUIRED",
                    "Confirm that every exported row has consent for ad-storage and conversion measurement.");
        }
        LinkedInAdsDestination destination = linkedInAdsDestination(siteId);
        Goal goal = goal(siteId, input.goalId(), true);
        String conversionUrn = linkedInAdsConversionUrn(siteId, input.goalId());
        List<NormalizedRow> normalized = normalizeRows(siteId, input.rows());
        ensureRowsMatchImportedConversions(siteId, input.goalId(), normalized, "linkedin_ads");
        Instant now = Instant.now();
        Map<String, RowInput> rawRows = new HashMap<>();
        for (RowInput row : input.rows()) {
            String key = TrackingIdentityHasher.hash(
                    siteId, "offline-conversion:" + row.conversionId().trim());
            rawRows.put(key, row);
        }
        Map<String, NavigableSet<Instant>> clickVisits = linkedinClickVisits(siteId, normalized);
        List<Map<String, Object>> events = new ArrayList<>(normalized.size());
        for (NormalizedRow row : normalized) {
            RowInput raw = rawRows.get(row.conversionKeyHash());
            if (!"linkedin_ads".equals(row.platform())) {
                throw invalid("Every row must use platform linkedin_ads.");
            }
            String clickId = field(raw.clickId(), 2_048, "li_fat_id", 0);
            if (!clickId.matches("[A-Za-z0-9._~-]{1,2048}")) {
                throw invalid("Every LinkedIn click ID must contain only letters, digits, '.', '_', '~' or '-'.");
            }
            if (row.convertedAt().isBefore(now.minus(Duration.ofDays(90)))
                    || row.convertedAt().isAfter(now)) {
                throw invalid("LinkedIn Conversions API accepts conversion timestamps from the past 90 days only.");
            }
            NavigableSet<Instant> visits = clickVisits.get(row.clickIdHash());
            Instant clickAt = visits == null ? null : visits.floor(row.convertedAt());
            if (clickAt == null || clickAt.isBefore(row.convertedAt().minus(Duration.ofDays(90)))) {
                throw new ControlPlaneException(
                        409,
                        "LINKEDIN_ADS_MATCHED_VISIT_REQUIRED",
                        "Every row must match a tracked LinkedIn ad click from this site within 90 days before conversion.");
            }
            Map<String, Object> userId = Map.of("idType", "LINKEDIN_FIRST_PARTY_ADS_TRACKING_UUID", "idValue", clickId);
            Map<String, Object> user = Map.of("userIds", List.of(userId));
            Map<String, Object> conversionValue = Map.of(
                    "currencyCode",
                    destination.currencyCode(),
                    "amount",
                    goal.fixedValue().toPlainString());
            Map<String, Object> event = new LinkedHashMap<>();
            event.put("conversion", conversionUrn);
            event.put("conversionHappenedAt", row.convertedAt().toEpochMilli());
            event.put("conversionValue", conversionValue);
            event.put("user", user);
            event.put(
                    "eventId",
                    TrackingIdentityHasher.hash(
                            siteId, "linkedin-ads-event:" + raw.conversionId().trim()));
            events.add(event);
        }
        Map<String, Object> payload = Map.of("elements", events);
        LinkedInConversionsGateway.Result result =
                linkedInAds.send(encryption.decrypt(destination.tokenCiphertext()), payload);
        return new LinkedInAdsTransferResult(events.size(), result.eventsReceived());
    }

    public XAdsConfigView xAdsConfig(UUID siteId) {
        Site site = readableSite(siteId);
        var member = access.member(site.organization.id);
        boolean canManage = member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN;
        ExistingXAdsConfig config = existingXAdsConfig(siteId);
        try (Connection connection = dataSource.getConnection()) {
            List<XAdsGoalMappingView> mappings = new ArrayList<>();
            try (PreparedStatement statement = connection.prepareStatement(
                    "select m.goal_id,g.name,m.event_id from analytics_x_ads_goal_mapping m "
                            + "join goal_definition g on g.id=m.goal_id and g.site_id=m.site_id "
                            + "where m.site_id=? and g.enabled order by g.name,m.goal_id")) {
                statement.setObject(1, siteId);
                try (ResultSet rows = statement.executeQuery()) {
                    while (rows.next()) {
                        mappings.add(new XAdsGoalMappingView(
                                rows.getObject(1, UUID.class), rows.getString(2), rows.getString(3)));
                    }
                }
            }
            return new XAdsConfigView(
                    canManage,
                    config != null,
                    config != null,
                    config == null ? null : config.pixelId(),
                    config == null ? null : config.currencyCode(),
                    List.copyOf(mappings));
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read X Ads Conversion API configuration", error);
        }
    }

    @Transactional
    public XAdsConfigView saveXAdsConfig(UUID siteId, XAdsConfigInput input) {
        writableSite(siteId);
        if (input == null) throw invalid("Enter an X Pixel ID, currency, and access token.");
        String pixelId = input.pixelId() == null ? "" : input.pixelId().strip();
        if (!pixelId.matches("[A-Za-z0-9._~-]{1,256}")) throw invalid("Enter a valid X Pixel ID.");
        String currencyCode =
                input.currencyCode() == null ? "" : input.currencyCode().strip().toUpperCase(Locale.ROOT);
        try {
            Currency.getInstance(currencyCode);
        } catch (IllegalArgumentException error) {
            throw invalid("Choose a valid three-letter ISO currency code.");
        }
        ExistingXAdsConfig existing = existingXAdsConfig(siteId);
        byte[] encryptedToken;
        if (input.accessToken() == null || input.accessToken().isBlank()) {
            if (existing == null || !existing.pixelId().equals(pixelId)) {
                throw new ControlPlaneException(
                        400,
                        "X_ADS_TOKEN_REQUIRED",
                        "Enter an access token on first connection or when changing the Pixel ID.");
            }
            encryptedToken = existing.tokenCiphertext();
        } else {
            String token = input.accessToken().strip();
            if (token.length() > 8_192) throw invalid("The X Pixel access token is too long.");
            encryptedToken = encryption.encrypt(token);
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_x_ads_capi_config(site_id,pixel_id,currency_code,access_token_ciphertext,updated_by,updated_at) "
                                + "values(?,?,?,?,?,now()) on conflict(site_id) do update set pixel_id=excluded.pixel_id,"
                                + "currency_code=excluded.currency_code,access_token_ciphertext=excluded.access_token_ciphertext,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setString(2, pixelId);
            statement.setString(3, currencyCode);
            statement.setBytes(4, encryptedToken);
            statement.setObject(5, access.userId());
            statement.executeUpdate();
            return xAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save X Ads Conversion API configuration", error);
        }
    }

    @Transactional
    public XAdsConfigView mapXAdsGoal(UUID siteId, UUID goalId, String eventIdValue) {
        writableSite(siteId);
        goal(siteId, goalId, true);
        String eventId = eventIdValue == null ? "" : eventIdValue.strip();
        if (!eventId.matches("[A-Za-z0-9._~-]{1,256}")) {
            throw invalid("Enter the X Event ID shown for the event in Events Manager.");
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "insert into analytics_x_ads_goal_mapping(site_id,goal_id,event_id,updated_by,updated_at) "
                                + "values(?,?,?,?,now()) on conflict(site_id,goal_id) do update set event_id=excluded.event_id,"
                                + "updated_by=excluded.updated_by,updated_at=now()")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            statement.setString(3, eventId);
            statement.setObject(4, access.userId());
            statement.executeUpdate();
            return xAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not save X Ads goal mapping", error);
        }
    }

    @Transactional
    public XAdsConfigView removeXAdsGoalMapping(UUID siteId, UUID goalId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "delete from analytics_x_ads_goal_mapping where site_id=? and goal_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            statement.executeUpdate();
            return xAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not remove X Ads goal mapping", error);
        }
    }

    @Transactional
    public XAdsConfigView removeXAdsConfig(UUID siteId) {
        writableSite(siteId);
        try (Connection connection = dataSource.getConnection()) {
            try (PreparedStatement mappings =
                    connection.prepareStatement("delete from analytics_x_ads_goal_mapping where site_id=?")) {
                mappings.setObject(1, siteId);
                mappings.executeUpdate();
            }
            try (PreparedStatement config =
                    connection.prepareStatement("delete from analytics_x_ads_capi_config where site_id=?")) {
                config.setObject(1, siteId);
                config.executeUpdate();
            }
            return xAdsConfig(siteId);
        } catch (SQLException error) {
            throw new IllegalStateException("Could not remove X Ads Conversion API configuration", error);
        }
    }

    public XAdsTransferResult transferToXAds(UUID siteId, XAdsTransferInput input) {
        writableSite(siteId);
        if (input == null
                || input.goalId() == null
                || input.rows() == null
                || input.rows().isEmpty()
                || input.rows().size() > MAX_X_ADS_ROWS) {
            throw invalid("Choose 1 to " + MAX_X_ADS_ROWS + " X conversion rows per send.");
        }
        if (!input.consentConfirmed()) {
            throw new ControlPlaneException(
                    400,
                    "X_ADS_CONSENT_CONFIRMATION_REQUIRED",
                    "Confirm that every exported row has consent for ad-storage and conversion measurement.");
        }
        XAdsDestination destination = xAdsDestination(siteId);
        Goal goal = goal(siteId, input.goalId(), true);
        String eventId = xAdsEventId(siteId, input.goalId());
        List<NormalizedRow> normalized = normalizeRows(siteId, input.rows());
        ensureRowsMatchImportedConversions(siteId, input.goalId(), normalized, "x_ads");
        Map<String, RowInput> rawRows = new HashMap<>();
        for (RowInput row : input.rows()) {
            String key = TrackingIdentityHasher.hash(
                    siteId, "offline-conversion:" + row.conversionId().trim());
            rawRows.put(key, row);
        }
        Map<String, NavigableSet<Instant>> clickVisits = xClickVisits(siteId, normalized);
        Instant now = Instant.now();
        List<Map<String, Object>> events = new ArrayList<>(normalized.size());
        for (NormalizedRow row : normalized) {
            RowInput raw = rawRows.get(row.conversionKeyHash());
            if (!"x_ads".equals(row.platform())) throw invalid("Every row must use platform x_ads.");
            String clickId = field(raw.clickId(), 2_048, "twclid", 0);
            if (row.convertedAt().isAfter(now)) throw invalid("X conversion timestamps cannot be in the future.");
            NavigableSet<Instant> visits = clickVisits.get(row.clickIdHash());
            Instant clickAt = visits == null ? null : visits.floor(row.convertedAt());
            if (clickAt == null || clickAt.isBefore(row.convertedAt().minus(Duration.ofDays(30)))) {
                throw new ControlPlaneException(
                        409,
                        "X_ADS_MATCHED_VISIT_REQUIRED",
                        "Every row must match a tracked X ad click from this site within the 30-day maximum click attribution window.");
            }
            Map<String, Object> identifier = Map.of("twclid", clickId);
            Map<String, Object> event = new LinkedHashMap<>();
            event.put("conversion_timestamp", row.convertedAt().toEpochMilli());
            event.put("identifiers", List.of(identifier));
            event.put("event_id", eventId);
            event.put(
                    "conversion_id",
                    TrackingIdentityHasher.hash(
                            siteId, "x-ads-conversion:" + raw.conversionId().trim()));
            if (goal.fixedValue() != null) event.put("value", goal.fixedValue());
            event.put("price_currency", destination.currencyCode());
            events.add(event);
        }
        Map<String, Object> payload = Map.of("conversions", events);
        XAdsConversionsGateway.Result result =
                xAds.send(destination.pixelId(), encryption.decrypt(destination.tokenCiphertext()), payload);
        return new XAdsTransferResult(events.size(), result.eventsReceived());
    }

    private Map<String, NavigableSet<Instant>> xClickVisits(UUID siteId, List<NormalizedRow> rows) {
        Set<String> clickHashes = new HashSet<>();
        Instant earliestConversion = rows.stream()
                .map(NormalizedRow::convertedAt)
                .min(Instant::compareTo)
                .orElseThrow();
        Instant latestConversion = rows.stream()
                .map(NormalizedRow::convertedAt)
                .max(Instant::compareTo)
                .orElseThrow();
        rows.forEach(row -> clickHashes.add(row.clickIdHash()));
        Map<String, NavigableSet<Instant>> visits = new HashMap<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select ad_click_id_hash,started_at from analytics_session where site_id=? "
                                + "and ad_click_platform='x_ads' and ad_click_id_hash=any(?) "
                                + "and started_at>=? and started_at<=? order by ad_click_id_hash,started_at")) {
            statement.setObject(1, siteId);
            statement.setArray(2, connection.createArrayOf("varchar", clickHashes.toArray(String[]::new)));
            statement.setTimestamp(3, Timestamp.from(earliestConversion.minus(Duration.ofDays(30))));
            statement.setTimestamp(4, Timestamp.from(latestConversion));
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    visits.computeIfAbsent(result.getString(1), ignored -> new TreeSet<>())
                            .add(result.getTimestamp(2).toInstant());
                }
            }
            return visits;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not match imported X click IDs to tracked visits", error);
        }
    }

    private ExistingXAdsConfig existingXAdsConfig(UUID siteId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select pixel_id,currency_code,access_token_ciphertext from analytics_x_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) return null;
                return new ExistingXAdsConfig(row.getString(1), row.getString(2), row.getBytes(3));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read X Ads Conversion API credentials", error);
        }
    }

    private XAdsDestination xAdsDestination(UUID siteId) {
        ExistingXAdsConfig config = existingXAdsConfig(siteId);
        if (config == null) {
            throw new ControlPlaneException(
                    409, "X_ADS_CONFIG_REQUIRED", "Save the X Pixel ID, currency, and access token first.");
        }
        return new XAdsDestination(config.pixelId(), config.currencyCode(), config.tokenCiphertext());
    }

    private String xAdsEventId(UUID siteId, UUID goalId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select event_id from analytics_x_ads_goal_mapping where site_id=? and goal_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) {
                    throw new ControlPlaneException(
                            409,
                            "X_ADS_GOAL_MAPPING_REQUIRED",
                            "Map this SeeRay goal to an X Events Manager Event ID first.");
                }
                return row.getString(1);
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not load X Ads goal mapping", error);
        }
    }

    private Map<String, NavigableSet<Instant>> linkedinClickVisits(UUID siteId, List<NormalizedRow> rows) {
        Set<String> clickHashes = new HashSet<>();
        Instant earliestConversion = rows.stream()
                .map(NormalizedRow::convertedAt)
                .min(Instant::compareTo)
                .orElseThrow();
        Instant latestConversion = rows.stream()
                .map(NormalizedRow::convertedAt)
                .max(Instant::compareTo)
                .orElseThrow();
        rows.forEach(row -> clickHashes.add(row.clickIdHash()));
        if (clickHashes.isEmpty()) return Map.of();
        String[] values = clickHashes.toArray(String[]::new);
        Map<String, NavigableSet<Instant>> visits = new HashMap<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select ad_click_id_hash,started_at from analytics_session where site_id=? "
                                + "and ad_click_platform='linkedin_ads' and ad_click_id_hash=any(?) "
                                + "and started_at>=? and started_at<=? order by ad_click_id_hash,started_at")) {
            statement.setObject(1, siteId);
            statement.setArray(2, connection.createArrayOf("varchar", values));
            statement.setTimestamp(3, Timestamp.from(earliestConversion.minus(Duration.ofDays(90))));
            statement.setTimestamp(4, Timestamp.from(latestConversion));
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    visits.computeIfAbsent(result.getString(1), ignored -> new TreeSet<>())
                            .add(result.getTimestamp(2).toInstant());
                }
            }
            return visits;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not match imported LinkedIn click IDs to tracked visits", error);
        }
    }

    private ExistingLinkedInAdsConfig existingLinkedInAdsConfig(UUID siteId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select currency_code,api_token_ciphertext from analytics_linkedin_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) return null;
                return new ExistingLinkedInAdsConfig(row.getString(1), row.getBytes(2));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read LinkedIn Conversions API credentials", error);
        }
    }

    private LinkedInAdsDestination linkedInAdsDestination(UUID siteId) {
        ExistingLinkedInAdsConfig config = existingLinkedInAdsConfig(siteId);
        if (config == null) {
            throw new ControlPlaneException(
                    409, "LINKEDIN_ADS_CONFIG_REQUIRED", "Save the LinkedIn access token and currency first.");
        }
        return new LinkedInAdsDestination(config.currencyCode(), config.tokenCiphertext());
    }

    private String linkedInAdsConversionUrn(UUID siteId, UUID goalId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select conversion_urn from analytics_linkedin_ads_goal_mapping where site_id=? and goal_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) {
                    throw new ControlPlaneException(
                            409,
                            "LINKEDIN_ADS_GOAL_MAPPING_REQUIRED",
                            "Map this SeeRay goal to a LinkedIn Conversions API conversion rule before sending events.");
                }
                return row.getString(1);
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not load LinkedIn conversion rule mapping", error);
        }
    }

    private Map<String, NavigableSet<Instant>> metaClickVisits(UUID siteId, List<NormalizedRow> rows) {
        Set<String> clickHashes = new HashSet<>();
        Instant earliestConversion = rows.stream()
                .map(NormalizedRow::convertedAt)
                .min(Instant::compareTo)
                .orElseThrow();
        Instant latestConversion = rows.stream()
                .map(NormalizedRow::convertedAt)
                .max(Instant::compareTo)
                .orElseThrow();
        rows.forEach(row -> clickHashes.add(row.clickIdHash()));
        if (clickHashes.isEmpty()) return Map.of();
        String[] values = clickHashes.toArray(String[]::new);
        Map<String, NavigableSet<Instant>> visits = new HashMap<>();
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select ad_click_id_hash,started_at from analytics_session where site_id=? "
                                + "and ad_click_platform='meta_ads' and ad_click_id_hash=any(?) "
                                + "and started_at>=? and started_at<=? order by ad_click_id_hash,started_at")) {
            statement.setObject(1, siteId);
            statement.setArray(2, connection.createArrayOf("varchar", values));
            statement.setTimestamp(3, Timestamp.from(earliestConversion.minus(Duration.ofDays(7))));
            statement.setTimestamp(4, Timestamp.from(latestConversion));
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    visits.computeIfAbsent(result.getString(1), ignored -> new TreeSet<>())
                            .add(result.getTimestamp(2).toInstant());
                }
            }
            return visits;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not match imported Meta click IDs to tracked visits", error);
        }
    }

    private ExistingMetaAdsConfig existingMetaAdsConfig(UUID siteId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select dataset_id,currency_code,api_token_ciphertext from analytics_meta_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) return null;
                return new ExistingMetaAdsConfig(row.getString(1), row.getString(2), row.getBytes(3));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read Meta Ads CAPI credentials", error);
        }
    }

    private MetaAdsDestination metaAdsDestination(UUID siteId) {
        ExistingMetaAdsConfig config = existingMetaAdsConfig(siteId);
        if (config == null) {
            throw new ControlPlaneException(
                    409, "META_ADS_CONFIG_REQUIRED", "Save the Meta dataset/pixel ID and access token first.");
        }
        return new MetaAdsDestination(config.datasetId(), config.currencyCode(), config.tokenCiphertext());
    }

    private String metaAdsEventName(UUID siteId, UUID goalId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select event_name from analytics_meta_ads_goal_mapping where site_id=? and goal_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) {
                    throw new ControlPlaneException(
                            409,
                            "META_ADS_GOAL_MAPPING_REQUIRED",
                            "Map this SeeRay goal to a Meta standard or custom event before sending conversions.");
                }
                return row.getString(1);
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not load Meta Ads goal mapping", error);
        }
    }

    private ExistingMicrosoftAdsConfig existingMicrosoftAdsConfig(UUID siteId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select tag_id,currency_code,api_token_ciphertext from analytics_microsoft_ads_capi_config where site_id=?")) {
            statement.setObject(1, siteId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) return null;
                return new ExistingMicrosoftAdsConfig(row.getString(1), row.getString(2), row.getBytes(3));
            }
        } catch (SQLException error) {
            throw new IllegalStateException("Could not read Microsoft Ads CAPI credentials", error);
        }
    }

    private MicrosoftAdsDestination microsoftAdsDestination(UUID siteId) {
        ExistingMicrosoftAdsConfig config = existingMicrosoftAdsConfig(siteId);
        if (config == null) {
            throw new ControlPlaneException(
                    409,
                    "MICROSOFT_ADS_CONFIG_REQUIRED",
                    "Save the Microsoft Ads UET tag and Conversions API token first.");
        }
        return new MicrosoftAdsDestination(config.tagId(), config.currencyCode(), config.tokenCiphertext());
    }

    private String microsoftAdsEventName(UUID siteId, UUID goalId) {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(
                        "select event_name from analytics_microsoft_ads_goal_mapping where site_id=? and goal_id=?")) {
            statement.setObject(1, siteId);
            statement.setObject(2, goalId);
            try (ResultSet row = statement.executeQuery()) {
                if (!row.next()) {
                    throw new ControlPlaneException(
                            409,
                            "MICROSOFT_ADS_GOAL_MAPPING_REQUIRED",
                            "Map this SeeRay goal to a Microsoft Ads custom event before sending conversions.");
                }
                return row.getString(1);
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not load Microsoft Ads goal mapping", error);
        }
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

    private void ensureRowsMatchImportedConversions(
            UUID siteId, UUID goalId, List<NormalizedRow> rows, String expectedPlatform) {
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
            throw new IllegalStateException("Could not verify imported ad-platform conversions", error);
        }
        for (NormalizedRow row : rows) {
            StoredConversion existing = stored.get(row.conversionKeyHash());
            if (existing == null
                    || !expectedPlatform.equals(existing.platform())
                    || !existing.clickIdHash().equals(row.clickIdHash())
                    || !existing.convertedAt().equals(row.convertedAt()))
                throw new ControlPlaneException(
                        409,
                        expectedPlatform.toUpperCase(Locale.ROOT) + "_EXPORT_ROW_NOT_IMPORTED",
                        "Every exported row must exactly match an already imported " + expectedPlatform
                                + " conversion for this site and goal.");
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
                // PostgreSQL TIMESTAMPTZ stores microseconds, so normalize before hashing/comparing imports.
                convertedAt = OffsetDateTime.parse(timestampText).toInstant().truncatedTo(ChronoUnit.MICROS);
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

    public record MicrosoftAdsConfigInput(String tagId, String currencyCode, String apiToken) {}

    public record MicrosoftAdsConfigView(
            boolean canManage,
            boolean configured,
            boolean credentialConfigured,
            String tagId,
            String currencyCode,
            List<MicrosoftAdsGoalMappingView> goalMappings) {}

    public record MicrosoftAdsGoalMappingView(UUID goalId, String goalName, String eventName) {}

    public record MicrosoftAdsTransferInput(UUID goalId, boolean consentConfirmed, List<RowInput> rows) {}

    public record MicrosoftAdsTransferResult(
            int rowsProcessed, int eventsReceived, List<Map<String, Object>> validationWarnings) {}

    public record MetaAdsConfigInput(String datasetId, String currencyCode, String apiToken) {}

    public record MetaAdsConfigView(
            boolean canManage,
            boolean configured,
            boolean credentialConfigured,
            String datasetId,
            String currencyCode,
            List<MetaAdsGoalMappingView> goalMappings) {}

    public record MetaAdsGoalMappingView(UUID goalId, String goalName, String eventName) {}

    public record MetaAdsTransferInput(
            UUID goalId, String actionSource, boolean consentConfirmed, List<RowInput> rows) {}

    public record MetaAdsTransferResult(int rowsProcessed, int eventsReceived) {}

    public record LinkedInAdsConfigInput(String currencyCode, String apiToken) {}

    public record LinkedInAdsConfigView(
            boolean canManage,
            boolean configured,
            boolean credentialConfigured,
            String currencyCode,
            List<LinkedInAdsGoalMappingView> goalMappings) {}

    public record LinkedInAdsGoalMappingView(UUID goalId, String goalName, String conversionUrn) {}

    public record LinkedInAdsTransferInput(UUID goalId, boolean consentConfirmed, List<RowInput> rows) {}

    public record LinkedInAdsTransferResult(int rowsProcessed, int eventsReceived) {}

    public record XAdsConfigInput(String pixelId, String currencyCode, String accessToken) {}

    public record XAdsConfigView(
            boolean canManage,
            boolean configured,
            boolean credentialConfigured,
            String pixelId,
            String currencyCode,
            List<XAdsGoalMappingView> goalMappings) {}

    public record XAdsGoalMappingView(UUID goalId, String goalName, String eventId) {}

    public record XAdsTransferInput(UUID goalId, boolean consentConfirmed, List<RowInput> rows) {}

    public record XAdsTransferResult(int rowsProcessed, int eventsReceived) {}

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

    private record ExistingMicrosoftAdsConfig(String tagId, String currencyCode, byte[] tokenCiphertext) {}

    private record MicrosoftAdsDestination(String tagId, String currencyCode, byte[] tokenCiphertext) {}

    private record ExistingMetaAdsConfig(String datasetId, String currencyCode, byte[] tokenCiphertext) {}

    private record MetaAdsDestination(String datasetId, String currencyCode, byte[] tokenCiphertext) {}

    private record ExistingLinkedInAdsConfig(String currencyCode, byte[] tokenCiphertext) {}

    private record LinkedInAdsDestination(String currencyCode, byte[] tokenCiphertext) {}

    private record ExistingXAdsConfig(String pixelId, String currencyCode, byte[] tokenCiphertext) {}

    private record XAdsDestination(String pixelId, String currencyCode, byte[] tokenCiphertext) {}

    private record StoredConversion(String platform, String clickIdHash, Instant convertedAt) {}

    private record NormalizedRow(String platform, Instant convertedAt, String conversionKeyHash, String clickIdHash) {}
}
