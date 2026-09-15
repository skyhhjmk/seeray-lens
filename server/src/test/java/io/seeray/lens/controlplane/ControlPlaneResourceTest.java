package io.seeray.lens.controlplane;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;
import static org.junit.jupiter.api.Assertions.*;

import io.quarkus.test.junit.QuarkusTest;
import io.seeray.lens.application.AnalyticsAggregationService;
import io.seeray.lens.application.AnalyticsFactBuilder;
import io.seeray.lens.application.HeatmapAggregationService;
import io.seeray.lens.domain.auth.AppUser;
import io.seeray.lens.domain.auth.AuthSession;
import io.seeray.lens.domain.auth.UserStatus;
import jakarta.inject.Inject;
import jakarta.transaction.UserTransaction;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Base64;
import java.util.List;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;

@QuarkusTest
class ControlPlaneResourceTest {
    @Inject
    UserTransaction transaction;

    @Inject
    DataSource dataSource;

    @Inject
    AnalyticsFactBuilder factBuilder;

    @Inject
    AnalyticsAggregationService aggregation;

    @Inject
    HeatmapAggregationService heatmapAggregation;

    @Test
    void registerLoginRefreshAndProtectedWorkspaceWork() throws Exception {
        String email = "user" + System.nanoTime() + "@example.test";
        Tokens registered = register(email);
        workspace(registered.access()).statusCode(200).body("size()", is(1));
        Tokens loggedIn = login(email);
        workspace(loggedIn.access()).statusCode(200);
        Tokens rotated = refresh(loggedIn.refresh());
        workspace(rotated.access()).statusCode(200);
        transaction.begin();
        try {
            List<AuthSession> sessions = AuthSession.list("user.email", email);
            assertTrue(sessions.stream().anyMatch(s -> s.revokedAt != null));
            assertTrue(sessions.stream()
                    .anyMatch(s -> s.revokedAt == null && !s.refreshTokenHash.equals(rotated.refresh())));
            assertTrue(sessions.stream().noneMatch(s -> s.refreshTokenHash.equals(loggedIn.refresh())));
            transaction.commit();
        } catch (Exception failure) {
            transaction.rollback();
            throw failure;
        }
        given().contentType("application/json")
                .body("{\"refreshToken\":\"" + loggedIn.refresh() + "\"}")
                .post("/api/v1/auth/refresh")
                .then()
                .statusCode(401);
        given().contentType("application/json")
                .body("{\"refreshToken\":\"" + rotated.refresh() + "\"}")
                .post("/api/v1/auth/logout")
                .then()
                .statusCode(204);
        given().contentType("application/json")
                .body("{\"refreshToken\":\"" + rotated.refresh() + "\"}")
                .post("/api/v1/auth/refresh")
                .then()
                .statusCode(401);
        given().contentType("application/json")
                .body("{\"refreshToken\":\"srlr_random_untrusted_token\"}")
                .post("/api/v1/auth/refresh")
                .then()
                .statusCode(401);
    }

    @Test
    void rejectsMissingMalformedAndForgedJwt() {
        workspace(null).statusCode(401);
        workspace("not-a-jwt").statusCode(401);
        workspace("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.invalid").statusCode(401);
        workspace(jwt("wrong", System.currentTimeMillis() / 1000 + 60)).statusCode(401);
        workspace(jwt("seeray-lens", System.currentTimeMillis() / 1000 - 60)).statusCode(401);
    }

    @Test
    void disabledUserCannotLoginOrRefresh() throws Exception {
        String email = "disabled" + System.nanoTime() + "@example.test";
        Tokens tokens = register(email);
        transaction.begin();
        try {
            AppUser user = AppUser.find("email", email).firstResult();
            user.status = UserStatus.DISABLED;
            transaction.commit();
        } catch (Exception failure) {
            transaction.rollback();
            throw failure;
        }
        given().contentType("application/json")
                .body("{\"email\":\"" + email + "\",\"password\":\"correct-horse-battery\"}")
                .post("/api/v1/auth/login")
                .then()
                .statusCode(403);
        given().contentType("application/json")
                .body("{\"refreshToken\":\"" + tokens.refresh() + "\"}")
                .post("/api/v1/auth/refresh")
                .then()
                .statusCode(403);
    }

    @Test
    void expiredRefreshTokenIsRejected() throws Exception {
        String email = "expired" + System.nanoTime() + "@example.test";
        Tokens tokens = register(email);
        transaction.begin();
        try {
            AuthSession session = AuthSession.find("user.email = ?1 order by createdAt desc", email)
                    .firstResult();
            session.expiresAt = Instant.now().minusSeconds(1);
            transaction.commit();
        } catch (Exception failure) {
            transaction.rollback();
            throw failure;
        }
        given().contentType("application/json")
                .body("{\"refreshToken\":\"" + tokens.refresh() + "\"}")
                .post("/api/v1/auth/refresh")
                .then()
                .statusCode(401);
    }

    @Test
    void blocksCrossWorkspaceAndSiteIdor() {
        Tokens a = register("a" + System.nanoTime() + "@example.test");
        Tokens b = register("b" + System.nanoTime() + "@example.test");
        String workspaceB = workspace(b.access()).extract().path("[0].id");
        given().header("Authorization", "Bearer " + a.access())
                .get("/api/v1/workspaces/" + workspaceB)
                .then()
                .statusCode(404);
        String siteB = given().header("Authorization", "Bearer " + b.access())
                .contentType("application/json")
                .body("{\"name\":\"Private\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceB + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + a.access())
                .get("/api/v1/sites/" + siteB)
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + a.access())
                .delete("/api/v1/sites/" + siteB)
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + a.access())
                .contentType("application/json")
                .body("{\"host\":\"private.example\",\"enabled\":true}")
                .post("/api/v1/sites/" + siteB + "/domains")
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + a.access())
                .get("/api/v1/workspaces/" + workspaceB + "/api-tokens")
                .then()
                .statusCode(404);
    }

    @Test
    void createsWorkspaceAndMakesCreatorOwner() {
        Tokens tokens = register("workspace" + System.nanoTime() + "@example.test");
        given().header("Authorization", "Bearer " + tokens.access())
                .contentType("application/json")
                .body("{\"name\":\"Product team\"}")
                .post("/api/v1/workspaces")
                .then()
                .statusCode(201)
                .body("name", is("Product team"))
                .body("role", is("owner"));
        workspace(tokens.access()).statusCode(200).body("size()", is(2));
    }

    @Test
    void collectPublishesAndPersistsSanitizedEventIdempotently() throws Exception {
        Tokens tokens = register("collect" + System.nanoTime() + "@example.test");
        var workspace = workspace(tokens.access()).extract().path("[0].id");
        var site = given().header("Authorization", "Bearer " + tokens.access())
                .contentType("application/json")
                .body("{\"name\":\"Collect\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract();
        String trackingId = site.path("trackingId");
        given().header("Authorization", "Bearer " + tokens.access())
                .contentType("application/json")
                .body("{\"host\":\"example.com\",\"enabled\":true}")
                .post("/api/v1/sites/" + site.path("id") + "/domains")
                .then()
                .statusCode(201);
        String eventId = UUID.randomUUID().toString();
        String body = "{\"schemaVersion\":1,\"siteId\":\"" + trackingId + "\",\"events\":[{\"eventId\":\"" + eventId
                + "\",\"type\":\"page_view\",\"visitorId\":\"00000000-0000-4000-8000-000000000001\",\"sessionId\":\"00000000-0000-4000-8000-000000000002\",\"url\":\"https://example.com/order?id=secret&utm_source=google#x\"}]}";
        given().contentType("application/json")
                .body(body)
                .post("/api/v1/collect")
                .then()
                .statusCode(202);
        given().contentType("application/json")
                .body(body)
                .post("/api/v1/collect")
                .then()
                .statusCode(202);
        long deadline = System.currentTimeMillis() + 8_000;
        long count;
        do {
            Thread.sleep(250);
            try (var connection = dataSource.getConnection();
                    var statement =
                            connection.prepareStatement("select count(*) from raw_event where client_event_id = ?")) {
                statement.setObject(1, UUID.fromString(eventId));
                try (var result = statement.executeQuery()) {
                    result.next();
                    count = result.getLong(1);
                }
            }
        } while (count == 0 && System.currentTimeMillis() < deadline);
        assertEquals(1, count);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "select page_path, utm_source from raw_event where client_event_id = ?")) {
            statement.setObject(1, UUID.fromString(eventId));
            try (var result = statement.executeQuery()) {
                assertTrue(result.next());
                assertEquals("/order", result.getString(1));
                assertEquals("google", result.getString(2));
            }
        }
        UUID siteUuid = UUID.fromString(site.path("id"));
        factBuilder.rebuild(
                siteUuid, Instant.now().minusSeconds(60), Instant.now().plusSeconds(60));
        try (var connection = dataSource.getConnection();
                var statement =
                        connection.prepareStatement("select count(*) from analytics_session where site_id = ?")) {
            statement.setObject(1, siteUuid);
            try (var result = statement.executeQuery()) {
                result.next();
                assertEquals(1, result.getLong(1));
            }
        }
    }

    @Test
    void collectorAcceptsCrossOriginBrowserPreflight() {
        given().header("Origin", "https://windblog.example")
                .header("Access-Control-Request-Method", "POST")
                .header("Access-Control-Request-Headers", "content-type")
                .options("/api/v1/collect")
                .then()
                .statusCode(200)
                .header("Access-Control-Allow-Origin", "https://windblog.example")
                .header("Access-Control-Allow-Methods", containsString("POST"));
    }

    @Test
    void heatmapConfigUsesTheHeatmapResourcePrefix() {
        Tokens owner = register("heatmap-config" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Heatmap config\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String path = "/api/v1/sites/" + site + "/heatmaps/config";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"enabled\":true,\"sampleRate\":37,\"rawRetentionDays\":30,\"aggregateRetentionDays\":180}")
                .put(path)
                .then()
                .statusCode(200)
                .body("enabled", is(true))
                .body("sampleRate", is(37));
        given().header("Authorization", "Bearer " + owner.access())
                .get(path)
                .then()
                .statusCode(200)
                .body("enabled", is(true))
                .body("sampleRate", is(37));
    }

    @Test
    void heatmapCollectorRejectsPayloadsOverFortyEightKiB() {
        String event = "{\"type\":\"move\",\"instanceId\":\"00000000-0000-4000-8000-000000000001\","
                + "\"url\":\"https://example.test/heatmap\",\"layoutVersion\":\"v1\",\"targetId\":\"page\","
                + "\"viewportWidth\":1000,\"viewportHeight\":800,\"contentWidth\":1000,\"contentHeight\":2400,"
                + "\"x\":320,\"y\":960,\"truncated\":false,\"dropped\":0}";
        String payload =
                "{\"schemaVersion\":1,\"siteId\":\"srl_public\",\"clientBatchId\":\"00000000-0000-4000-8000-000000000002\",\"events\":["
                        + String.join(",", java.util.Collections.nCopies(500, event)) + "]}";
        given().contentType("application/json")
                .body(payload)
                .post("/api/v1/collect/heatmaps")
                .then()
                .statusCode(413)
                .body("code", is("HEATMAP_PAYLOAD_TOO_LARGE"));
    }

    @Test
    void heatmapScrollDenominatorRequiresAnInitialStartEvent() throws Exception {
        Tokens owner = register("heatmap-denominator" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Heatmap denominator\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        UUID siteId = UUID.fromString(site);
        String instance = "00000000-0000-4000-8000-000000000001";
        String common = "\"instanceId\":\"" + instance + "\",\"url\":\"https://example.test/heatmap\","
                + "\"layoutVersion\":\"v1\",\"targetId\":\"page\",\"viewportWidth\":1000,\"viewportHeight\":800,"
                + "\"contentWidth\":1000,\"contentHeight\":2400,\"truncated\":false,\"dropped\":0";
        insertHeatmapRaw(siteId, "[{\"type\":\"scroll\"," + common + ",\"scrollBins\":[50]}]");
        heatmapAggregation.processPending(100);
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement("select count(*) from heatmap_instance_fact where site_id=?")) {
            p.setObject(1, siteId);
            try (var rows = p.executeQuery()) {
                rows.next();
                assertEquals(0, rows.getLong(1));
            }
        }
        insertHeatmapRaw(siteId, "[{\"type\":\"start\"," + common + "}]");
        heatmapAggregation.processPending(100);
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement("select count(*) from heatmap_instance_fact where site_id=?")) {
            p.setObject(1, siteId);
            try (var rows = p.executeQuery()) {
                rows.next();
                assertEquals(1, rows.getLong(1));
            }
        }
    }

    @Test
    void heatmapScrollStatsUseAllStartedInstancesAsTheDenominator() throws Exception {
        Tokens owner = register("heatmap-scroll-ratio" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Heatmap ratio\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        UUID siteId = UUID.fromString(site);
        String common = "\"url\":\"https://example.test/heatmap\",\"layoutVersion\":\"v1\","
                + "\"targetId\":\"page\",\"viewportWidth\":1000,\"viewportHeight\":800,"
                + "\"contentWidth\":1000,\"contentHeight\":2400,\"truncated\":false,\"dropped\":0";
        String first = "00000000-0000-4000-8000-000000000011";
        String second = "00000000-0000-4000-8000-000000000012";
        insertHeatmapRaw(
                siteId,
                "[{\"type\":\"start\",\"instanceId\":\"" + first + "\"," + common
                        + "},{\"type\":\"scroll\",\"instanceId\":\"" + first + "\"," + common
                        + ",\"scrollBins\":[50]}]");
        insertHeatmapRaw(siteId, "[{\"type\":\"start\",\"instanceId\":\"" + second + "\"," + common + "}]");
        heatmapAggregation.processPending(100);
        UUID variantId;
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement("select id from heatmap_variant where site_id=?")) {
            p.setObject(1, siteId);
            try (var rows = p.executeQuery()) {
                assertTrue(rows.next());
                variantId = rows.getObject(1, UUID.class);
            }
        }
        String day = LocalDate.now().toString();
        var response = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site + "/heatmaps/stats?variantId=" + variantId + "&from=" + day + "&to=" + day
                        + "&type=scroll")
                .then()
                .statusCode(200)
                .extract();
        assertEquals(2, ((Number) response.path("instances")).intValue());
        assertEquals(2, ((Number) response.path("depth.find { it.bin == 50 }.instances")).intValue());
        assertEquals(0.5d, ((Number) response.path("depth.find { it.bin == 50 }.ratio")).doubleValue());
    }

    @Test
    void factsSplitTimeoutAndCountExactDailyVisitors() throws Exception {
        Tokens tokens = register("facts" + System.nanoTime() + "@example.test");
        String workspace = workspace(tokens.access()).extract().path("[0].id");
        var site = given().header("Authorization", "Bearer " + tokens.access())
                .contentType("application/json")
                .body("{\"name\":\"Facts\",\"timezone\":\"Asia/Tokyo\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract();
        UUID siteId = UUID.fromString(site.path("id"));
        Instant base = Instant.parse("2026-09-13T15:00:00Z");
        insertRaw(siteId, "visitor-a", "session-a", "page_view", base.plusSeconds(1800), "/a");
        insertRaw(siteId, "visitor-a", "session-a", "page_view", base, "/first");
        insertRaw(siteId, "visitor-a", "session-a", "custom", base.plusSeconds(60), "/first");
        insertRaw(siteId, "visitor-a", "session-a", "page_view", base.plusSeconds(1801), "/second");
        insertRaw(siteId, "visitor-a", "session-a", "page_view", base.plusSeconds(1801 + 24 * 3600), "/third");
        insertRaw(siteId, "visitor-b", "session-b", "page_view", base.plusSeconds(120), "/b");
        factBuilder.rebuild(siteId, base.minusSeconds(1), base.plusSeconds(3 * 24 * 3600));
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement("select count(*) from analytics_session where site_id=?")) {
            p.setObject(1, siteId);
            try (var r = p.executeQuery()) {
                r.next();
                assertEquals(4, r.getLong(1));
            }
        }
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement("select count(*) from visitor_day_fact where site_id=?")) {
            p.setObject(1, siteId);
            try (var r = p.executeQuery()) {
                r.next();
                assertEquals(3, r.getLong(1));
            }
        }
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement("select count(*) from analytics_session where site_id=? and is_bounce")) {
            p.setObject(1, siteId);
            try (var r = p.executeQuery()) {
                r.next();
                assertEquals(3, r.getLong(1));
            }
        }
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement(
                        "select count(*) from analytics_session where site_id=? and visitor_type='returning'")) {
            p.setObject(1, siteId);
            try (var r = p.executeQuery()) {
                r.next();
                assertEquals(2, r.getLong(1));
            }
        }
    }

    @Test
    void analyticsApisUseAggregatesAndExactRangeVisitors() throws Exception {
        Tokens owner = register("analytics" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Analytics\",\"timezone\":\"Asia/Tokyo\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        UUID siteId = UUID.fromString(site);
        Instant dayOne = Instant.parse("2026-09-01T15:00:00Z"); // Sep 2 in Tokyo
        // A appears on both days, so daily UV is 2 + 2 while range UV must be 3.
        insertAnalyticsRaw(siteId, "a", "a1", "page_view", dayOne, "/a", null, null, null, null);
        insertAnalyticsRaw(
                siteId, "b", "b1", "page_view", dayOne.plusSeconds(1), "/a", "ref.example", null, null, null);
        insertAnalyticsRaw(
                siteId,
                "a",
                "a2",
                "page_view",
                dayOne.plusSeconds(86_400),
                "/b",
                null,
                "newsletter",
                "email",
                "launch");
        insertAnalyticsRaw(siteId, "c", "c1", "custom", dayOne.plusSeconds(86_401), "/b", null, null, null, null);
        insertAnalyticsRaw(siteId, "c", "c1", "page_view", dayOne.plusSeconds(86_420), "/b", null, null, null, null);
        insertAnalyticsRaw(siteId, "c", "c1", "page_view", dayOne.plusSeconds(86_431), "/b", null, null, null, null);
        aggregation.rebuild(siteId, java.time.LocalDate.of(2026, 9, 2), java.time.LocalDate.of(2026, 9, 3));
        String base = "/api/v1/sites/" + site + "/analytics";
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/overview?from=2026-09-02&to=2026-09-03")
                .then()
                .statusCode(200)
                .body("pageViews", is(5))
                .body("uniqueVisitors", is(3))
                .body("sessions", is(4))
                .body("bounceRate", is(0.75f))
                .body("averageSessionDurationMs", is(7500));
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/timeseries?from=2026-09-02&to=2026-09-03")
                .then()
                .statusCode(200)
                .body("size()", is(2))
                .body("uniqueVisitors", contains(2, 2));
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/pages?from=2026-09-02&to=2026-09-03")
                .then()
                .statusCode(200)
                .body("path", contains("/b", "/a"))
                .body("pageViews", contains(3, 2));
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/traffic?from=2026-09-02&to=2026-09-03")
                .then()
                .statusCode(200)
                .body("channel", hasItems("direct", "referral", "campaign"));
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/events?from=2026-09-02&to=2026-09-03")
                .then()
                .statusCode(200)
                .body("eventType", hasItems("page_view", "custom"));
        Tokens outsider = register("outsider" + System.nanoTime() + "@example.test");
        given().header("Authorization", "Bearer " + outsider.access())
                .get(base + "/overview")
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/overview?from=2026-09-04&to=2026-09-03")
                .then()
                .statusCode(400);
    }

    private void insertAnalyticsRaw(
            UUID siteId,
            String visitor,
            String session,
            String type,
            Instant occurred,
            String path,
            String referrer,
            String source,
            String medium,
            String campaign)
            throws Exception {
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement(
                        "insert into raw_event(ingest_id,site_id,client_event_id,client_visitor_id,client_session_id,received_at,occurred_at,event_type,page_host,page_path,referrer_host,utm_source,utm_medium,utm_campaign,event_data,ingest_version) values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?::jsonb,1)")) {
            p.setObject(1, UUID.randomUUID());
            p.setObject(2, siteId);
            p.setObject(3, UUID.randomUUID());
            p.setString(4, visitor);
            p.setString(5, session);
            p.setTimestamp(6, java.sql.Timestamp.from(occurred.plusSeconds(1)));
            p.setTimestamp(7, java.sql.Timestamp.from(occurred));
            p.setString(8, type);
            p.setString(9, "example.test");
            p.setString(10, path);
            p.setString(11, referrer);
            p.setString(12, source);
            p.setString(13, medium);
            p.setString(14, campaign);
            p.setString(15, "custom".equals(type) ? "{\"interaction\":true}" : "{}");
            p.executeUpdate();
        }
    }

    private void insertRaw(UUID siteId, String visitor, String session, String type, Instant occurred, String path)
            throws Exception {
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement(
                        "insert into raw_event(ingest_id,site_id,client_event_id,client_visitor_id,client_session_id,received_at,occurred_at,event_type,page_path,event_data,ingest_version) values(?,?,?,?,?,?,?,?,?,'{}',1)")) {
            p.setObject(1, UUID.randomUUID());
            p.setObject(2, siteId);
            p.setObject(3, UUID.randomUUID());
            p.setString(4, visitor);
            p.setString(5, session);
            p.setTimestamp(6, java.sql.Timestamp.from(occurred.plusSeconds(1)));
            p.setTimestamp(7, java.sql.Timestamp.from(occurred));
            p.setString(8, type);
            p.setString(9, path);
            p.executeUpdate();
        }
    }

    private void insertHeatmapRaw(UUID siteId, String payload) throws Exception {
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement(
                        "insert into heatmap_raw_batch(id,site_id,client_batch_id,received_at,payload,effective_sample_rate) values(?,?,?,now(),?::jsonb,100)")) {
            p.setObject(1, UUID.randomUUID());
            p.setObject(2, siteId);
            p.setObject(3, UUID.randomUUID());
            p.setString(4, payload);
            p.executeUpdate();
        }
    }

    private static Tokens register(String email) {
        return tokens(
                "/api/v1/auth/register",
                "{\"email\":\"" + email + "\",\"password\":\"correct-horse-battery\",\"displayName\":\"Ada\"}");
    }

    private static Tokens login(String email) {
        return tokens("/api/v1/auth/login", "{\"email\":\"" + email + "\",\"password\":\"correct-horse-battery\"}");
    }

    private static Tokens refresh(String refresh) {
        return tokens("/api/v1/auth/refresh", "{\"refreshToken\":\"" + refresh + "\"}");
    }

    private static Tokens tokens(String path, String body) {
        var response = given().contentType("application/json")
                .body(body)
                .post(path)
                .then()
                .statusCode(200)
                .extract();
        return new Tokens(response.path("accessToken"), response.path("refreshToken"));
    }

    private static io.restassured.response.ValidatableResponse workspace(String access) {
        var request = given();
        if (access != null) request.header("Authorization", "Bearer " + access);
        return request.get("/api/v1/workspaces").then();
    }

    private record Tokens(String access, String refresh) {}

    private static String jwt(String issuer, long exp) {
        try {
            String h = b64("{\"alg\":\"HS256\",\"typ\":\"JWT\"}"),
                    p =
                            b64("{\"sub\":\"00000000-0000-0000-0000-000000000001\",\"iss\":\"" + issuer
                                    + "\",\"iat\":1,\"exp\":" + exp + "}");
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(
                    "change-me-in-production-change-me-in-production".getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return h + "." + p + "."
                    + Base64.getUrlEncoder()
                            .withoutPadding()
                            .encodeToString(mac.doFinal((h + "." + p).getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new AssertionError(e);
        }
    }

    private static String b64(String value) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }
}
