package io.seeray.lens.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.UuidV7;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.*;
import java.util.*;
import javax.sql.DataSource;

/** Rebuildable, deterministic semantic fact builder. Raw events remain the source of truth. */
@ApplicationScoped
public class AnalyticsFactBuilder {
    private static final Duration SESSION_TIMEOUT = Duration.ofMinutes(30);
    private static final Duration MAX_SESSION_LIFETIME = Duration.ofHours(24);
    private static final Duration MAX_CLOCK_SKEW = Duration.ofHours(24);
    private final DataSource dataSource;
    private final ObjectMapper mapper;

    @Inject
    public AnalyticsFactBuilder(DataSource dataSource, ObjectMapper mapper) {
        this.dataSource = dataSource;
        this.mapper = mapper;
    }

    /** Rebuilds all facts for a site; the range is a reconciliation hint and raw facts are never replaced by cache state. */
    @Transactional
    public void rebuild(UUID siteId, Instant from, Instant to) {
        try (Connection c = dataSource.getConnection()) {
            ZoneId zone = ZoneId.of(siteTimezone(c, siteId));
            List<Event> events = load(c, siteId, from, to);
            Map<String, VisitorAcc> visitors = new LinkedHashMap<>();
            for (Event event : events) {
                if (event.visitorId == null || event.sessionId == null) continue;
                Instant time = analyticsTime(event.occurredAt, event.receivedAt);
                VisitorAcc visitor = visitors.computeIfAbsent(event.visitorId, k -> new VisitorAcc(k, time));
                visitor.days.add(time.atZone(zone).toLocalDate());
                visitor.lastSeen = max(visitor.lastSeen, time);
                SessionAcc current =
                        visitor.sessions.isEmpty() ? null : visitor.sessions.get(visitor.sessions.size() - 1);
                if (current == null
                        || !current.clientSessionId.equals(event.sessionId)
                        || Duration.between(current.startedAt, time).compareTo(SESSION_TIMEOUT) >= 0
                        || Duration.between(current.startedAt, time).compareTo(MAX_SESSION_LIFETIME) >= 0) {
                    current = new SessionAcc(event.sessionId, time, visitor.sessions.isEmpty());
                    visitor.sessions.add(current);
                }
                current.accept(event, time, mapper);
            }
            deleteFacts(c, siteId);
            Map<String, UUID> visitorIds = insertVisitors(c, siteId, visitors.values());
            insertSessions(c, siteId, visitors.values(), visitorIds);
            insertVisitorDays(c, siteId, visitors.values(), visitorIds);
        } catch (SQLException e) {
            throw new IllegalStateException("Could not rebuild analytics facts", e);
        }
    }

    private static Instant analyticsTime(Instant occurred, Instant received) {
        if (occurred.isBefore(received.minus(MAX_CLOCK_SKEW)) || occurred.isAfter(received.plus(MAX_CLOCK_SKEW)))
            return received;
        return occurred;
    }

    private static Instant max(Instant a, Instant b) {
        return a.compareTo(b) >= 0 ? a : b;
    }

    private static String siteTimezone(Connection c, UUID site) throws SQLException {
        try (PreparedStatement p = c.prepareStatement("select timezone from site where id=?")) {
            p.setObject(1, site);
            try (ResultSet r = p.executeQuery()) {
                if (!r.next()) throw new IllegalArgumentException("site not found");
                return r.getString(1);
            }
        }
    }

    private static List<Event> load(Connection c, UUID site, Instant from, Instant to) throws SQLException {
        String sql =
                "select client_visitor_id,client_session_id,event_type,occurred_at,received_at,page_path,page_host,referrer_host,utm_source,utm_medium,utm_campaign,duration_ms,event_data,page_title,utm_term,utm_content from raw_event where site_id=? order by occurred_at,received_at,ingest_id";
        List<Event> out = new ArrayList<>();
        try (PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, site);
            try (ResultSet r = p.executeQuery()) {
                while (r.next())
                    out.add(new Event(
                            r.getString(1),
                            r.getString(2),
                            r.getString(3),
                            r.getTimestamp(4).toInstant(),
                            r.getTimestamp(5).toInstant(),
                            r.getString(6),
                            r.getString(7),
                            r.getString(8),
                            r.getString(9),
                            r.getString(10),
                            r.getString(11),
                            (Integer) r.getObject(12),
                            r.getString(13),
                            r.getString(14),
                            r.getString(15),
                            r.getString(16)));
            }
        }
        return out;
    }

    private static void deleteFacts(Connection c, UUID site) throws SQLException {
        try (PreparedStatement p = c.prepareStatement("delete from visitor_day_fact where site_id=?")) {
            p.setObject(1, site);
            p.executeUpdate();
        }
        try (PreparedStatement p = c.prepareStatement("delete from analytics_session where site_id=?")) {
            p.setObject(1, site);
            p.executeUpdate();
        }
        try (PreparedStatement p = c.prepareStatement("delete from analytics_visitor where site_id=?")) {
            p.setObject(1, site);
            p.executeUpdate();
        }
    }

    private static Map<String, UUID> insertVisitors(Connection c, UUID site, Collection<VisitorAcc> values)
            throws SQLException {
        Map<String, UUID> ids = new HashMap<>();
        try (PreparedStatement p = c.prepareStatement(
                "insert into analytics_visitor(id,site_id,client_visitor_id,first_seen_at,last_seen_at,first_session_at,last_session_at,session_count) values(?,?,?,?,?,?,?,?)")) {
            for (VisitorAcc v : values) {
                v.id = UuidV7.next();
                ids.put(v.clientId, v.id);
                p.setObject(1, v.id);
                p.setObject(2, site);
                p.setString(3, v.clientId);
                p.setTimestamp(4, Timestamp.from(v.firstSeen));
                p.setTimestamp(5, Timestamp.from(v.lastSeen));
                p.setTimestamp(6, Timestamp.from(v.sessions.get(0).startedAt));
                p.setTimestamp(7, Timestamp.from(v.sessions.get(v.sessions.size() - 1).startedAt));
                p.setInt(8, v.sessions.size());
                p.addBatch();
            }
            p.executeBatch();
        }
        return ids;
    }

    private static void insertSessions(Connection c, UUID site, Collection<VisitorAcc> values, Map<String, UUID> ids)
            throws SQLException {
        try (PreparedStatement p = c.prepareStatement(
                "insert into analytics_session(id,site_id,visitor_id,client_session_id,started_at,last_activity_at,ended_at,entry_page,exit_page,page_view_count,event_count,duration_ms,is_bounce,visitor_type,initial_referrer_host,initial_page_host,initial_utm_source,initial_utm_medium,initial_utm_campaign,browser,browser_version,operating_system,operating_system_version,device_type,language,screen_width,screen_height,viewport_width,viewport_height,pixel_ratio,entry_page_title,exit_page_title,country_code,continent_code,region_code,region_name,city,geo_timezone,initial_utm_term,initial_utm_content) values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")) {
            for (VisitorAcc v : values)
                for (SessionAcc s : v.sessions) {
                    p.setObject(1, s.id = UuidV7.next());
                    p.setObject(2, site);
                    p.setObject(3, ids.get(v.clientId));
                    p.setString(4, s.clientSessionId);
                    p.setTimestamp(5, Timestamp.from(s.startedAt));
                    p.setTimestamp(6, Timestamp.from(s.lastActivity));
                    p.setTimestamp(7, Timestamp.from(s.lastActivity));
                    p.setString(8, s.entryPage);
                    p.setString(9, s.exitPage);
                    p.setInt(10, s.pageViews);
                    p.setInt(11, s.events);
                    p.setLong(12, Duration.between(s.startedAt, s.lastActivity).toMillis());
                    p.setBoolean(13, s.pageViews == 1 && !s.interaction);
                    p.setString(14, s.newVisitor ? "new" : "returning");
                    p.setString(15, s.referrer);
                    p.setString(16, s.host);
                    p.setString(17, s.utm);
                    p.setString(18, s.utmMedium);
                    p.setString(19, s.utmCampaign);
                    p.setString(20, s.browser);
                    p.setString(21, s.browserVersion);
                    p.setString(22, s.operatingSystem);
                    p.setString(23, s.operatingSystemVersion);
                    p.setString(24, s.deviceType);
                    p.setString(25, s.language);
                    p.setObject(26, s.screenWidth);
                    p.setObject(27, s.screenHeight);
                    p.setObject(28, s.viewportWidth);
                    p.setObject(29, s.viewportHeight);
                    p.setObject(30, s.pixelRatio);
                    p.setString(31, s.entryPageTitle);
                    p.setString(32, s.exitPageTitle);
                    p.setString(33, s.countryCode);
                    p.setString(34, s.continentCode);
                    p.setString(35, s.regionCode);
                    p.setString(36, s.region);
                    p.setString(37, s.city);
                    p.setString(38, s.geoTimezone);
                    p.setString(39, s.utmTerm);
                    p.setString(40, s.utmContent);
                    p.addBatch();
                }
            p.executeBatch();
        }
    }

    private static void insertVisitorDays(Connection c, UUID site, Collection<VisitorAcc> values, Map<String, UUID> ids)
            throws SQLException {
        try (PreparedStatement p = c.prepareStatement(
                "insert into visitor_day_fact(site_id,business_date,visitor_id) values(?,?,?) on conflict do nothing")) {
            for (VisitorAcc v : values) {
                for (LocalDate d : v.days) {
                    p.setObject(1, site);
                    p.setObject(2, d);
                    p.setObject(3, ids.get(v.clientId));
                    p.addBatch();
                }
            }
            p.executeBatch();
        }
    }

    private record Event(
            String visitorId,
            String sessionId,
            String type,
            Instant occurredAt,
            Instant receivedAt,
            String path,
            String host,
            String referrer,
            String utm,
            String utmMedium,
            String utmCampaign,
            Integer duration,
            String data,
            String title,
            String utmTerm,
            String utmContent) {}

    private static final class VisitorAcc {
        String clientId;
        UUID id;
        Instant firstSeen, lastSeen;
        Set<LocalDate> days = new HashSet<>();
        List<SessionAcc> sessions = new ArrayList<>();

        VisitorAcc(String id, Instant t) {
            clientId = id;
            firstSeen = t;
            lastSeen = t;
        }
    }

    private static final class SessionAcc {
        String clientSessionId, entryPage, exitPage, referrer, host, utm, utmMedium, utmCampaign, utmTerm, utmContent;
        String entryPageTitle, exitPageTitle;
        String browser, browserVersion, operatingSystem, operatingSystemVersion, deviceType, language;
        String countryCode, continentCode, regionCode, region, city, geoTimezone;
        Integer screenWidth, screenHeight, viewportWidth, viewportHeight;
        Double pixelRatio;
        UUID id;
        Instant startedAt, lastActivity;
        int pageViews, events;
        boolean interaction, newVisitor;

        SessionAcc(String id, Instant t, boolean n) {
            clientSessionId = id;
            startedAt = t;
            lastActivity = t;
            newVisitor = n;
        }

        void accept(Event e, Instant t, ObjectMapper m) {
            if (!"web_vital".equals(e.type)) events++;
            if (!"heartbeat".equals(e.type)) lastActivity = max(lastActivity, t);
            JsonNode data;
            try {
                data = m.readTree(e.data == null ? "{}" : e.data);
            } catch (Exception ignored) {
                data = m.createObjectNode();
            }
            if ("page_view".equals(e.type)) {
                if (pageViews == 0) {
                    captureTechnology(data.path("context"));
                    captureLocation(data.path("context"));
                }
                pageViews++;
                if (entryPage == null) {
                    entryPage = e.path;
                    entryPageTitle = e.title;
                }
                exitPage = e.path;
                exitPageTitle = e.title;
            }
            if (referrer == null) referrer = e.referrer;
            if (host == null) host = e.host;
            if (utm == null) utm = e.utm;
            if (utmMedium == null) utmMedium = e.utmMedium;
            if (utmCampaign == null) utmCampaign = e.utmCampaign;
            if (utmTerm == null) utmTerm = e.utmTerm;
            if (utmContent == null) utmContent = e.utmContent;
            interaction |= data.path("interaction").asBoolean(false)
                    || data.path("data").path("interaction").asBoolean(false);
        }

        private void captureTechnology(JsonNode context) {
            browser = category(
                    context,
                    "browser",
                    Set.of("Chrome", "Safari", "Firefox", "Edge", "Opera", "Samsung Internet", "Other"));
            browserVersion = version(context, "browserVersion");
            operatingSystem = category(
                    context,
                    "operatingSystem",
                    Set.of("Android", "iOS", "Windows", "macOS", "Linux", "ChromeOS", "Other"));
            operatingSystemVersion = version(context, "operatingSystemVersion");
            deviceType = category(context, "deviceType", Set.of("mobile", "tablet", "desktop", "other"));
            language = boundedText(context, "language", 35);
            screenWidth = boundedInt(context, "screenWidth");
            screenHeight = boundedInt(context, "screenHeight");
            viewportWidth = boundedInt(context, "viewportWidth");
            viewportHeight = boundedInt(context, "viewportHeight");
            JsonNode ratio = context.path("pixelRatio");
            if (ratio.isNumber() && ratio.doubleValue() >= 0.25 && ratio.doubleValue() <= 8.0)
                pixelRatio = ratio.doubleValue();
        }

        private void captureLocation(JsonNode context) {
            countryCode = code(context, "countryCode", Locale.getISOCountries());
            continentCode = code(context, "continentCode", new String[] {"AF", "AN", "AS", "EU", "NA", "OC", "SA"});
            regionCode = boundedToken(context, "regionCode", 16);
            region = boundedText(context, "region", 120);
            city = boundedText(context, "city", 120);
            geoTimezone = boundedText(context, "geoTimezone", 64);
            if (countryCode == null) {
                continentCode = null;
                regionCode = null;
                region = null;
                city = null;
                geoTimezone = null;
            }
        }

        private static String code(JsonNode context, String field, String[] allowed) {
            String value = boundedText(context, field, 2);
            if (value == null) return null;
            String normalized = value.toUpperCase(Locale.ROOT);
            return Arrays.asList(allowed).contains(normalized) ? normalized : null;
        }

        private static String boundedToken(JsonNode context, String field, int limit) {
            String value = boundedText(context, field, limit);
            return value != null && value.matches("[A-Za-z0-9-]{1," + limit + "}")
                    ? value.toUpperCase(Locale.ROOT)
                    : null;
        }

        private static String category(JsonNode context, String field, Set<String> allowed) {
            String value = boundedText(context, field, 32);
            return value != null && allowed.contains(value) ? value : null;
        }

        private static String version(JsonNode context, String field) {
            String value = boundedText(context, field, 24);
            return value != null && value.matches("[A-Za-z0-9._-]{1,24}") ? value : null;
        }

        private static String boundedText(JsonNode context, String field, int limit) {
            JsonNode value = context.path(field);
            if (!value.isTextual()) return null;
            String text = value.asText();
            return !text.isBlank() && text.length() <= limit ? text : null;
        }

        private static Integer boundedInt(JsonNode context, String field) {
            JsonNode value = context.path(field);
            if (!value.isIntegralNumber() || value.intValue() < 1 || value.intValue() > 10000) return null;
            return value.intValue();
        }
    }
}
