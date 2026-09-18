package io.seeray.lens.controlplane;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;
import static org.junit.jupiter.api.Assertions.*;

import io.quarkus.test.junit.QuarkusTest;
import io.seeray.lens.application.AnalyticsAggregationService;
import io.seeray.lens.application.AnalyticsFactBuilder;
import io.seeray.lens.application.HeatmapAggregationService;
import io.seeray.lens.application.RawAnalyticsRetentionService;
import io.seeray.lens.domain.auth.AppUser;
import io.seeray.lens.domain.auth.AuthSession;
import io.seeray.lens.domain.auth.UserStatus;
import jakarta.inject.Inject;
import jakarta.transaction.UserTransaction;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
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
    RawAnalyticsRetentionService rawRetention;

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
    void workspaceRollupAggregatesAllowedSitesAndRejectsCrossWorkspaceSelections() throws Exception {
        Tokens owner = register("rollup" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String firstSite = createSite(owner.access(), workspaceId, "Rollup one");
        String secondSite = createSite(owner.access(), workspaceId, "Rollup two");
        LocalDate day = LocalDate.of(2026, 9, 4);
        try (var connection = dataSource.getConnection();
                var siteStatement = connection.prepareStatement(
                        "insert into analytics_site_daily(site_id,business_date,page_view_count,session_count,bounced_session_count) values(?,?,?,?,?)");
                var channelStatement = connection.prepareStatement(
                        "insert into analytics_traffic_daily(site_id,business_date,channel,source,medium,campaign,session_count) values(?,?,?,?,?,?,?)")) {
            for (var row : List.of(new Object[] {firstSite, 10L, 2L, 1L}, new Object[] {secondSite, 20L, 4L, 1L})) {
                UUID siteId = UUID.fromString((String) row[0]);
                siteStatement.setObject(1, siteId);
                siteStatement.setObject(2, day);
                siteStatement.setLong(3, (Long) row[1]);
                siteStatement.setLong(4, (Long) row[2]);
                siteStatement.setLong(5, (Long) row[3]);
                siteStatement.executeUpdate();
                channelStatement.setObject(1, siteId);
                channelStatement.setObject(2, day);
                channelStatement.setString(3, "campaign");
                channelStatement.setString(4, "google");
                channelStatement.setString(5, "cpc");
                channelStatement.setString(6, "spring");
                channelStatement.setLong(7, (Long) row[2]);
                channelStatement.executeUpdate();
            }
        }

        String path = "/api/v1/workspaces/" + workspaceId + "/analytics/rollup";
        String rangeBody = "{\"from\":\"" + day + "\",\"to\":\"" + day + "\"}";
        var full = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(rangeBody)
                .post(path)
                .then()
                .statusCode(200)
                .body("siteCount", is(2))
                .body("pageViews", is(30))
                .body("sessions", is(6))
                .body("siteVisitors", is(0))
                .body("daily[0].pageViews", is(30))
                .body("channels[0].channel", is("campaign"))
                .body("channels[0].sessions", is(6))
                .extract();
        assertEquals(1.0 / 3.0, ((Number) full.path("bounceRate")).doubleValue(), 0.0000001);

        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"siteIds\":[\"" + firstSite + "\"],\"from\":\"" + day + "\",\"to\":\"" + day + "\"}")
                .post(path)
                .then()
                .statusCode(200)
                .body("siteCount", is(1))
                .body("pageViews", is(10));

        Tokens outsider = register("rollup-outsider" + System.nanoTime() + "@example.test");
        given().header("Authorization", "Bearer " + outsider.access())
                .contentType("application/json")
                .body(rangeBody)
                .post(path)
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + outsider.access())
                .contentType("application/json")
                .body("{\"siteIds\":[\"" + firstSite + "\"],\"from\":\"" + day + "\",\"to\":\"" + day + "\"}")
                .post(path)
                .then()
                .statusCode(404);
    }

    private String createSite(String access, String workspaceId, String name) {
        return given().header("Authorization", "Bearer " + access)
                .contentType("application/json")
                .body("{\"name\":\"" + name + "\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
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
    void workspaceOwnerManagesMembersAndCanTransferOwnershipSafely() {
        String ownerEmail = "member-owner" + System.nanoTime() + "@example.test";
        String firstMemberEmail = "member-first" + System.nanoTime() + "@example.test";
        String secondMemberEmail = "member-second" + System.nanoTime() + "@example.test";
        Tokens owner = register(ownerEmail);
        Tokens firstMember = register(firstMemberEmail);
        Tokens secondMember = register(secondMemberEmail);
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String path = "/api/v1/workspaces/" + workspaceId + "/members";

        var first = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"email\":\"" + firstMemberEmail.toUpperCase(Locale.ROOT) + "\",\"role\":\"viewer\"}")
                .post(path)
                .then()
                .statusCode(201)
                .body("email", is(firstMemberEmail))
                .body("role", is("viewer"))
                .body("currentUser", is(false))
                .extract();
        String firstMemberId = first.path("userId");

        given().header("Authorization", "Bearer " + firstMember.access())
                .get(path)
                .then()
                .statusCode(403);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"email\":\"" + firstMemberEmail + "\",\"role\":\"viewer\"}")
                .post(path)
                .then()
                .statusCode(409);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"email\":\"not-registered@example.test\",\"role\":\"viewer\"}")
                .post(path)
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"email\":\"" + secondMemberEmail + "\",\"role\":\"owner\"}")
                .post(path)
                .then()
                .statusCode(400);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"role\":\"admin\"}")
                .patch(path + "/" + firstMemberId)
                .then()
                .statusCode(200)
                .body("role", is("admin"));

        String secondMemberId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"email\":\"" + secondMemberEmail + "\",\"role\":\"viewer\"}")
                .post(path)
                .then()
                .statusCode(201)
                .extract()
                .path("userId");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{}")
                .post(path + "/" + firstMemberId + "/transfer-ownership")
                .then()
                .statusCode(200)
                .body("role", is("owner"));
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/workspaces/" + workspaceId)
                .then()
                .statusCode(200)
                .body("role", is("admin"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"role\":\"viewer\"}")
                .patch(path + "/" + secondMemberId)
                .then()
                .statusCode(403);

        given().header("Authorization", "Bearer " + firstMember.access())
                .get(path)
                .then()
                .statusCode(200)
                .body("size()", is(3))
                .body("find { it.currentUser }.role", is("owner"));
        given().header("Authorization", "Bearer " + firstMember.access())
                .delete(path + "/" + secondMemberId)
                .then()
                .statusCode(204);
        given().header("Authorization", "Bearer " + firstMember.access())
                .delete(path + "/" + firstMemberId)
                .then()
                .statusCode(409);
        given().header("Authorization", "Bearer " + secondMember.access())
                .get("/api/v1/workspaces/" + workspaceId)
                .then()
                .statusCode(404);
    }

    @Test
    void siteConsentPolicyIsPersistedAndReturnedToManagementUi() {
        Tokens owner = register("site-consent" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        var site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Consent site\",\"timezone\":\"UTC\",\"requireConsent\":true}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .body("requireConsent", is(true))
                .extract();
        String siteId = site.path("id");
        String path = "/api/v1/sites/" + siteId;

        given().header("Authorization", "Bearer " + owner.access())
                .get(path)
                .then()
                .statusCode(200)
                .body("requireConsent", is(true));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Consent site renamed\",\"timezone\":\"UTC\","
                        + "\"defaultLanguage\":\"en\",\"trackingEnabled\":true,"
                        + "\"rawRetentionDays\":30,\"aggregateRetentionDays\":730}")
                .patch(path)
                .then()
                .statusCode(200)
                .body("requireConsent", is(true));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Consent site renamed\",\"timezone\":\"UTC\","
                        + "\"defaultLanguage\":\"en\",\"trackingEnabled\":true,\"requireConsent\":false,"
                        + "\"rawRetentionDays\":30,\"aggregateRetentionDays\":730}")
                .patch(path)
                .then()
                .statusCode(200)
                .body("requireConsent", is(false));
    }

    @Test
    void analyticsAnnotationsAreSiteScopedDateFilteredAndEditable() {
        Tokens owner = register("annotations" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String siteId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Annotations site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String path = "/api/v1/sites/" + siteId + "/annotations";
        LocalDate today = LocalDate.now(ZoneId.of("UTC"));
        String yesterday = today.minusDays(1).toString();

        String annotationId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"date\":\"" + yesterday + "\",\"note\":\"Campaign launch\"}")
                .post(path)
                .then()
                .statusCode(201)
                .body("date", is(yesterday))
                .body("note", is("Campaign launch"))
                .extract()
                .path("id");

        given().header("Authorization", "Bearer " + owner.access())
                .get(path + "?from=" + yesterday + "&to=" + yesterday)
                .then()
                .statusCode(200)
                .body("canManage", is(true))
                .body("annotations.size()", is(1))
                .body("annotations[0].id", is(annotationId));
        given().header("Authorization", "Bearer " + owner.access())
                .get(path + "?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("annotations.size()", is(0));

        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"date\":\"" + today + "\",\"note\":\"Launch delayed\"}")
                .put(path + "/" + annotationId)
                .then()
                .statusCode(200)
                .body("date", is(today.toString()))
                .body("note", is("Launch delayed"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"date\":\"" + today + "\",\"note\":\"   \"}")
                .post(path)
                .then()
                .statusCode(400)
                .body("code", is("ANNOTATION_INVALID"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{}")
                .post(path)
                .then()
                .statusCode(400)
                .body("code", is("ANNOTATION_INVALID"));
        given().header("Authorization", "Bearer " + owner.access())
                .get(path + "?from=" + today.minusDays(400) + "&to=" + today)
                .then()
                .statusCode(400)
                .body("code", is("ANNOTATION_RANGE_INVALID"));
        given().header("Authorization", "Bearer " + owner.access())
                .delete(path + "/" + annotationId)
                .then()
                .statusCode(204);
        given().header("Authorization", "Bearer " + owner.access())
                .get(path + "?from=" + today.minusDays(1) + "&to=" + today)
                .then()
                .statusCode(200)
                .body("annotations.size()", is(0));

        String audit = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/audit-log?from=" + today.minusDays(1) + "&to=" + today)
                .then()
                .statusCode(200)
                .extract()
                .asString();
        assertTrue(audit.contains("\"resource\":\"annotations\""));
        assertTrue(audit.contains("\"action\":\"CREATE\""));
        assertTrue(audit.contains("\"action\":\"UPDATE\""));
        assertTrue(audit.contains("\"action\":\"DELETE\""));
        assertFalse(audit.contains("Campaign launch"));
        assertFalse(audit.contains("Launch delayed"));
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
                + "\",\"type\":\"page_view\",\"visitorId\":\"00000000-0000-4000-8000-000000000001\",\"sessionId\":\"00000000-0000-4000-8000-000000000002\",\"url\":\"https://example.com/order?id=secret&utm_source=google#x\",\"title\":\"Order confirmation\",\"context\":{\"browser\":\"Chrome\",\"browserVersion\":\"132\",\"operatingSystem\":\"Linux\",\"operatingSystemVersion\":\"6.8\",\"deviceType\":\"desktop\",\"language\":\"zh-CN\",\"screenWidth\":1920,\"screenHeight\":1080,\"viewportWidth\":1440,\"viewportHeight\":900,\"pixelRatio\":1.5}}]}";
        given().header("cf-ipcountry", "US")
                .header("cf-ipcontinent", "NA")
                .header("cf-region-code", "CA")
                .header("cf-region", "California")
                .header("cf-ipcity", "San Francisco")
                .header("cf-timezone", "America/Los_Angeles")
                .contentType("application/json")
                .body(body)
                .post("/api/v1/collect")
                .then()
                .statusCode(202);
        given().header("cf-ipcountry", "US")
                .header("cf-ipcontinent", "NA")
                .header("cf-region-code", "CA")
                .header("cf-region", "California")
                .header("cf-ipcity", "San Francisco")
                .header("cf-timezone", "America/Los_Angeles")
                .contentType("application/json")
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
                        "select page_path, page_title, utm_source, event_data->'context'->>'browser',event_data->'context'->>'countryCode' from raw_event where client_event_id = ?")) {
            statement.setObject(1, UUID.fromString(eventId));
            try (var result = statement.executeQuery()) {
                assertTrue(result.next());
                assertEquals("/order", result.getString(1));
                assertEquals("Order confirmation", result.getString(2));
                assertEquals("google", result.getString(3));
                assertEquals("Chrome", result.getString(4));
                assertEquals("US", result.getString(5));
            }
        }
        UUID siteUuid = UUID.fromString(site.path("id"));
        String today = LocalDate.now(java.time.ZoneId.of("UTC")).toString();
        aggregation.rebuild(siteUuid, LocalDate.parse(today), LocalDate.parse(today));
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "select count(*),min(browser),min(browser_version),min(device_type),min(country_code),min(city) from analytics_session where site_id = ?")) {
            statement.setObject(1, siteUuid);
            try (var result = statement.executeQuery()) {
                result.next();
                assertEquals(1, result.getLong(1));
                assertEquals("Chrome", result.getString(2));
                assertEquals("132", result.getString(3));
                assertEquals("desktop", result.getString(4));
                assertEquals("US", result.getString(5));
                assertEquals("San Francisco", result.getString(6));
            }
        }
        List<java.util.Map<String, Object>> technology = given().header("Authorization", "Bearer " + tokens.access())
                .get("/api/v1/sites/" + site.path("id") + "/analytics/technology?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        assertTrue(technology.stream()
                .anyMatch(row -> "Browser".equals(row.get("dimension")) && "Chrome".equals(row.get("value"))));
        assertTrue(technology.stream()
                .anyMatch(row ->
                        "Screen size".equals(row.get("dimension")) && "1920 × 1080 px".equals(row.get("value"))));
        given().header("Authorization", "Bearer " + tokens.access())
                .get("/api/v1/sites/" + site.path("id") + "/analytics/locations?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("sourceConfigured", is(true))
                .body("rows.find { it.level == 'country' }.label", is("United States"))
                .body("rows.find { it.level == 'city' }.label", is("San Francisco · California · United States"));
        given().header("Authorization", "Bearer " + tokens.access())
                .get("/api/v1/sites/" + site.path("id") + "/analytics/realtime?windowMinutes=30&limit=100")
                .then()
                .statusCode(200)
                .body("size()", is(1))
                .body("[0].visitorId", is("00000000-0000-4000-8000-000000000001"))
                .body("[0].currentTitle", is("Order confirmation"))
                .body("[0].pageViews", is(1))
                .body("[0].countryCode", is("US"))
                .body("[0].city", is("San Francisco"))
                .body("[0].actions[0].eventType", is("page_view"))
                .body("[0].actions[0].path", is("/order"))
                .body("[0].actions[0].at", notNullValue());
        given().header("Authorization", "Bearer " + tokens.access())
                .get("/api/v1/sites/" + site.path("id") + "/analytics/page-titles?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("title", hasItem("Order confirmation"))
                .body("path", hasItem("/order"))
                .body("pageViews", hasItem(1));
        given().header("Authorization", "Bearer " + tokens.access())
                .get("/api/v1/sites/" + site.path("id") + "/analytics/entry-exit?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("flow", contains("entry", "exit"))
                .body("title", contains("Order confirmation", "Order confirmation"))
                .body("sessions", contains(1, 1));
    }

    @Test
    void formAnalyticsAggregatesExplicitFormsWithoutReturningFieldData() throws Exception {
        Tokens owner = register("form-analytics" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String siteId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Forms site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        UUID site = UUID.fromString(siteId);
        LocalDate reportDay = LocalDate.now(ZoneId.of("UTC")).minusDays(1);
        Instant base = reportDay.atTime(10, 0).toInstant(java.time.ZoneOffset.UTC);
        String visitorOne = UUID.randomUUID().toString();
        String sessionOne = UUID.randomUUID().toString();
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "form_view",
                base,
                "/signup",
                "{\"name\":\"signup\",\"data\":{\"formId\":\"signup\"}}");
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "form_start",
                base.plusSeconds(1),
                "/signup",
                "{\"name\":\"signup\",\"data\":{\"formId\":\"signup\"}}");
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "form_field",
                base.plusSeconds(2),
                "/signup",
                "{\"name\":\"signup\",\"data\":{\"formId\":\"signup\",\"fieldType\":\"text\",\"name\":\"email\",\"value\":\"secret@example.test\"}}");
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "form_submit",
                base.plusSeconds(3),
                "/signup",
                "{\"name\":\"signup\",\"data\":{\"formId\":\"signup\"}}");
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "form_success",
                base.plusSeconds(4),
                "/signup",
                "{\"name\":\"signup\",\"data\":{\"formId\":\"signup\"}}");

        String visitorTwo = UUID.randomUUID().toString();
        String sessionTwo = UUID.randomUUID().toString();
        insertRaw(
                site,
                visitorTwo,
                sessionTwo,
                "form_view",
                base.plusSeconds(10),
                "/signup",
                "{\"name\":\"signup\",\"data\":{\"formId\":\"signup\"}}");
        insertRaw(
                site,
                visitorTwo,
                sessionTwo,
                "form_start",
                base.plusSeconds(11),
                "/signup",
                "{\"name\":\"signup\",\"data\":{\"formId\":\"signup\"}}");
        insertRaw(
                site,
                visitorTwo,
                sessionTwo,
                "form_error",
                base.plusSeconds(12),
                "/signup",
                "{\"name\":\"signup\",\"data\":{\"formId\":\"signup\",\"fieldType\":\"text\"}}");
        insertRaw(
                site,
                visitorTwo,
                sessionTwo,
                "form_field_time",
                base.plusSeconds(13),
                "/signup",
                "{\"name\":\"signup\",\"data\":{\"formId\":\"signup\",\"fieldType\":\"text\"}}");
        insertRaw(
                site,
                UUID.randomUUID().toString(),
                UUID.randomUUID().toString(),
                "form_view",
                base.plusSeconds(20),
                "/unsafe",
                "{\"name\":\"unsafe id\",\"data\":{\"formId\":\"unsafe id\"}}");
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "update raw_event set duration_ms=1500 where site_id=? and client_session_id=? and event_type='form_field_time'")) {
            statement.setObject(1, site);
            statement.setString(2, sessionTwo);
            statement.executeUpdate();
        }

        var response = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/forms?from=" + reportDay + "&to=" + reportDay)
                .then()
                .statusCode(200)
                .extract()
                .response();
        assertEquals("signup", response.path("rows[0].formId"));
        assertEquals(1, ((Number) response.path("rows.size()")).intValue());
        assertEquals("/signup", response.path("rows[0].pagePath"));
        assertEquals(2L, ((Number) response.path("rows[0].views")).longValue());
        assertEquals(2L, ((Number) response.path("rows[0].starts")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].fieldInteractions")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].validationErrors")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].submits")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].successes")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].abandonments")).longValue());
        assertEquals(1500L, ((Number) response.path("rows[0].averageFieldTimeMs")).longValue());
        assertEquals(0.5, ((Number) response.path("rows[0].conversionRate")).doubleValue(), 0.001);
        assertFalse(response.asString().contains("secret@example.test"));
        assertFalse(response.asString().contains("email"));
    }

    @Test
    void mediaAnalyticsAggregatesPlaybackMilestonesWithoutReturningMediaUrls() throws Exception {
        Tokens owner = register("media-analytics" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String siteId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Media site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        UUID site = UUID.fromString(siteId);
        LocalDate reportDay = LocalDate.now(ZoneId.of("UTC")).minusDays(1);
        Instant base = reportDay.atTime(10, 0).toInstant(java.time.ZoneOffset.UTC);
        String visitorOne = UUID.randomUUID().toString();
        String sessionOne = UUID.randomUUID().toString();
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "media_start",
                base,
                "/watch",
                "{\"name\":\"launch-video\",\"data\":{\"mediaId\":\"launch-video\",\"mediaType\":\"video\",\"source\":\"https://cdn.example.test/private.mp4?token=secret\",\"title\":\"Internal launch\"}}");
        for (int milestone : new int[] {25, 50, 75, 90}) {
            insertRaw(
                    site,
                    visitorOne,
                    sessionOne,
                    "media_progress",
                    base.plusSeconds(milestone),
                    "/watch",
                    "{\"name\":\"launch-video\",\"data\":{\"mediaId\":\"launch-video\",\"mediaType\":\"video\",\"progressPercent\":"
                            + milestone + "}}");
        }
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "media_complete",
                base.plusSeconds(120),
                "/watch",
                "{\"name\":\"launch-video\",\"data\":{\"mediaId\":\"launch-video\",\"mediaType\":\"video\",\"mediaDurationSeconds\":120}}");
        String visitorTwo = UUID.randomUUID().toString();
        String sessionTwo = UUID.randomUUID().toString();
        insertRaw(
                site,
                visitorTwo,
                sessionTwo,
                "media_start",
                base.plusSeconds(200),
                "/watch",
                "{\"name\":\"launch-video\",\"data\":{\"mediaId\":\"launch-video\",\"mediaType\":\"video\"}}");

        var response = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/media?from=" + reportDay + "&to=" + reportDay)
                .then()
                .statusCode(200)
                .extract()
                .response();
        assertEquals("launch-video", response.path("rows[0].mediaId"));
        assertEquals("/watch", response.path("rows[0].pagePath"));
        assertEquals(2L, ((Number) response.path("rows[0].starts")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].reached25")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].reached50")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].reached75")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].reached90")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].completions")).longValue());
        assertEquals(1L, ((Number) response.path("rows[0].incompleteSessions")).longValue());
        assertEquals(2L, ((Number) response.path("rows[0].uniqueVisitors")).longValue());
        assertEquals(120, ((Number) response.path("rows[0].averageDurationSeconds")).intValue());
        assertEquals(0.5, ((Number) response.path("rows[0].completionRate")).doubleValue(), 0.001);
        assertFalse(response.asString().contains("private.mp4"));
        assertFalse(response.asString().contains("secret"));
        assertFalse(response.asString().contains("Internal launch"));
    }

    @Test
    void clientCrashCollectorRedactsSensitiveDataAndReportClustersAnonymousErrors() throws Exception {
        Tokens owner = register("crash-analytics" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        var createdSite = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Crash site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract();
        String site = createdSite.path("id");
        String trackingId = createdSite.path("trackingId");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"host\":\"example.com\",\"enabled\":true}")
                .post("/api/v1/sites/" + site + "/domains")
                .then()
                .statusCode(201);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(
                        "{\"releaseId\":\"web-1\",\"bundlePath\":\"/assets/app.js\","
                                + "\"sourceMap\":{\"version\":3,\"file\":\"app.js\",\"sources\":[\"../src/app.ts\"],"
                                + "\"sourcesContent\":[\"private-source-code\"],\"names\":[\"render\"],\"mappings\":\"AAAAA\"}}")
                .put("/api/v1/sites/" + site + "/crash-source-maps")
                .then()
                .statusCode(200)
                .body("releaseId", equalTo("web-1"))
                .body("sourceCount", equalTo(1));
        String viewerEmail = "crash-viewer" + System.nanoTime() + "@example.test";
        Tokens viewer = register(viewerEmail);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"email\":\"" + viewerEmail + "\",\"role\":\"viewer\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/members")
                .then()
                .statusCode(201);
        given().header("Authorization", "Bearer " + viewer.access())
                .get("/api/v1/sites/" + site + "/crash-source-maps")
                .then()
                .statusCode(200)
                .body("canManage", equalTo(false))
                .body("maps.size()", equalTo(1));
        given().header("Authorization", "Bearer " + viewer.access())
                .contentType("application/json")
                .body("{\"releaseId\":\"web-1\",\"bundlePath\":\"/assets/app.js\","
                        + "\"sourceMap\":{\"version\":3,\"sources\":[\"../src/app.ts\"],"
                        + "\"names\":[\"render\"],\"mappings\":\"AAAAA\"}}")
                .put("/api/v1/sites/" + site + "/crash-source-maps")
                .then()
                .statusCode(403);
        try (var connection = dataSource.getConnection();
                var statement =
                        connection.prepareStatement("select map_json::text from crash_source_map where site_id=?")) {
            statement.setObject(1, UUID.fromString(site));
            try (var result = statement.executeQuery()) {
                assertTrue(result.next());
                assertFalse(result.getString(1).contains("private-source-code"));
            }
        }
        LocalDate today = LocalDate.now(ZoneId.of("UTC"));
        Instant occurred = Instant.now();
        String visitor = UUID.randomUUID().toString();
        String session = UUID.randomUUID().toString();
        String eventData = "\"category\":\"error\",\"action\":\"javascript\",\"name\":\"TypeError\","
                + "\"visitorId\":\"" + visitor + "\",\"sessionId\":\"" + session + "\","
                + "\"occurredAt\":\"" + occurred + "\",\"title\":\"Private customer title\","
                + "\"referrer\":\"https://example.com/private?token=referrer-secret\","
                + "\"context\":{\"browser\":\"Chrome\",\"operatingSystem\":\"Linux\",\"deviceType\":\"desktop\"},"
                + "\"properties\":{\"errorName\":\"TypeError\","
                + "\"message\":\"Request https://api.example.test/users?token=url-secret failed for alice@example.test; Bearer bearer-secret; id 550e8400-e29b-41d4-a716-446655440000; account 123456789\","
                + "\"sourcePath\":\"/assets/app.js?api_key=source-secret\",\"line\":1,\"column\":1,\"releaseId\":\"web-1\","
                + "\"stack\":\"private stack with stack-secret\"}}";
        String firstEvent = "{\"eventId\":\"" + UUID.randomUUID() + "\",\"type\":\"client_error\","
                + "\"occurredAt\":\"" + occurred
                + "\",\"url\":\"https://example.com/accounts/12345678?token=page-secret\","
                + eventData;
        String secondEvent = "{\"eventId\":\"" + UUID.randomUUID() + "\",\"type\":\"client_error\","
                + "\"occurredAt\":\"" + occurred.plusSeconds(1) + "\",\"url\":\"https://example.com/checkout\","
                + eventData.replace(
                        "\"visitorId\":\"" + visitor + "\",\"sessionId\":\"" + session + "\"",
                        "\"visitorId\":\"" + UUID.randomUUID() + "\",\"sessionId\":\"" + UUID.randomUUID() + "\"");
        given().contentType("application/json")
                .body("{\"schemaVersion\":1,\"siteId\":\"" + trackingId + "\",\"events\":[" + firstEvent + ","
                        + secondEvent + "]}")
                .post("/api/v1/collect")
                .then()
                .statusCode(202);

        long deadline = System.currentTimeMillis() + 8_000;
        long count = 0;
        do {
            Thread.sleep(250);
            try (var connection = dataSource.getConnection();
                    var statement = connection.prepareStatement(
                            "select count(*) from raw_event where site_id=? and event_type='client_error'")) {
                statement.setObject(1, UUID.fromString(site));
                try (var result = statement.executeQuery()) {
                    result.next();
                    count = result.getLong(1);
                }
            }
        } while (count < 2 && System.currentTimeMillis() < deadline);
        assertEquals(2, count);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "select page_path,page_title,referrer_path,client_visitor_id,client_session_id,event_data::text from raw_event where site_id=? and event_type='client_error' order by page_path")) {
            statement.setObject(1, UUID.fromString(site));
            try (var result = statement.executeQuery()) {
                assertTrue(result.next());
                assertEquals("/accounts/<id>", result.getString(1));
                assertNull(result.getString(2));
                assertNull(result.getString(3));
                assertNull(result.getString(4));
                assertNull(result.getString(5));
                String stored = result.getString(6);
                for (String privateValue : List.of(
                        "url-secret",
                        "source-secret",
                        "referrer-secret",
                        "alice@example.test",
                        "bearer-secret",
                        "stack-secret",
                        "Private customer title",
                        visitor,
                        session))
                    assertFalse(stored.contains(privateValue), "sensitive crash field was stored: " + privateValue);
                assertTrue(stored.contains("<email>"));
                assertTrue(stored.contains("<url>"));
                assertTrue(result.next());
                assertEquals("/checkout", result.getString(1));
                assertNull(result.getString(4));
                assertNull(result.getString(5));
                assertFalse(result.next());
            }
        }

        var report = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site + "/analytics/crashes?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .extract()
                .response();
        assertEquals(2L, ((Number) report.path("occurrences")).longValue());
        assertEquals(1, ((Number) report.path("issueCount")).intValue());
        assertEquals("TypeError", report.path("rows[0].errorName"));
        assertEquals("/src/app.ts", report.path("rows[0].sourcePath"));
        assertEquals(1, ((Number) report.path("rows[0].line")).intValue());
        assertEquals(1, ((Number) report.path("rows[0].column")).intValue());
        assertEquals("render", report.path("rows[0].functionName"));
        assertEquals(2, ((Number) report.path("rows[0].affectedPages")).intValue());
        assertEquals("Chrome", report.path("rows[0].browsers"));
        assertFalse(report.asString().contains(visitor));
        assertFalse(report.asString().contains(session));
        assertFalse(report.asString().contains("stack-secret"));
        assertFalse(report.asString().contains("page-secret"));
    }

    @Test
    void siteSearchReportCountsTermsZeroResultsAndSavedSegment() throws Exception {
        Tokens owner = register("site-search" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String siteId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Search site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");

        UUID site = UUID.fromString(siteId);
        LocalDate reportDay = LocalDate.now(ZoneId.of("UTC")).minusDays(1);
        Instant base = reportDay.atTime(10, 0).toInstant(java.time.ZoneOffset.UTC);
        String visitorOne = UUID.randomUUID().toString();
        String sessionOne = UUID.randomUUID().toString();
        insertRaw(site, visitorOne, sessionOne, "page_view", base, "/search");
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "site_search",
                base.plusSeconds(1),
                "/search",
                "{\"category\":\"site_search\",\"action\":\"catalog\",\"name\":\"red shoes\","
                        + "\"data\":{\"keyword\":\"red shoes\",\"searchCategory\":\"catalog\",\"resultsCount\":0}}");
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "site_search",
                base.plusSeconds(2),
                "/search",
                "{\"category\":\"site_search\",\"action\":\"catalog\",\"name\":\"red shoes\","
                        + "\"data\":{\"keyword\":\"red shoes\",\"searchCategory\":\"catalog\",\"resultsCount\":7}}");

        String visitorTwo = UUID.randomUUID().toString();
        String sessionTwo = UUID.randomUUID().toString();
        insertRaw(site, visitorTwo, sessionTwo, "page_view", base.plusSeconds(20), "/search");
        insertRaw(site, visitorTwo, sessionTwo, "page_view", base.plusSeconds(21), "/results");
        insertRaw(
                site,
                visitorTwo,
                sessionTwo,
                "site_search",
                base.plusSeconds(22),
                "/search",
                "{\"category\":\"site_search\",\"name\":\"size guide\","
                        + "\"data\":{\"keyword\":\"size guide\",\"resultsCount\":\"unknown\"}}");

        String boundaryVisitor = UUID.randomUUID().toString();
        String boundarySession = UUID.randomUUID().toString();
        Instant previousDay = reportDay.minusDays(1).atTime(23, 59, 50).toInstant(java.time.ZoneOffset.UTC);
        Instant searchAfterMidnight =
                reportDay.atStartOfDay(ZoneId.of("UTC")).plusSeconds(5).toInstant();
        insertRaw(site, boundaryVisitor, boundarySession, "page_view", previousDay, "/search");
        insertRaw(
                site,
                boundaryVisitor,
                boundarySession,
                "site_search",
                searchAfterMidnight,
                "/search",
                "{\"category\":\"site_search\",\"name\":\"overnight\","
                        + "\"data\":{\"keyword\":\"overnight\",\"searchCategory\":\"docs\"}}");
        factBuilder.rebuild(site, previousDay.minusSeconds(5), base.plusSeconds(30));

        String report = "/api/v1/sites/" + siteId + "/analytics/site-search?from=" + reportDay + "&to=" + reportDay;
        given().header("Authorization", "Bearer " + owner.access())
                .get(report)
                .then()
                .statusCode(200)
                .body("searches", is(4))
                .body("uniqueVisitors", is(3))
                .body("sessions", is(3))
                .body("zeroResultSearches", is(1))
                .body("measuredResultSearches", is(2))
                .body("averageResultsCount", is(3.5f))
                .body("terms[0].keyword", is("red shoes"))
                .body("terms[0].category", is("catalog"))
                .body("terms[0].searches", is(2))
                .body("terms[0].zeroResultSearches", is(1));

        String segmentId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Multi-page searchers\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"page_views\",\"operator\":\"at_least\",\"value\":\"2\"}]}")
                .post("/api/v1/sites/" + siteId + "/segments")
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .get(report + "&segmentId=" + segmentId)
                .then()
                .statusCode(200)
                .body("searches", is(1))
                .body("uniqueVisitors", is(1))
                .body("measuredResultSearches", is(0))
                .body("terms[0].keyword", is("size guide"));

        Tokens outsider = register("site-search-outsider" + System.nanoTime() + "@example.test");
        given().header("Authorization", "Bearer " + outsider.access())
                .get(report)
                .then()
                .statusCode(404);
    }

    @Test
    void contentReportAggregatesImpressionsInteractionsAndSavedSegment() throws Exception {
        Tokens owner = register("content-report" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String siteId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Content site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");

        UUID site = UUID.fromString(siteId);
        LocalDate reportDay = LocalDate.now(ZoneId.of("UTC")).minusDays(1);
        Instant base = reportDay.atTime(10, 0).toInstant(java.time.ZoneOffset.UTC);
        String visitorOne = UUID.randomUUID().toString();
        String sessionOne = UUID.randomUUID().toString();
        insertRaw(site, visitorOne, sessionOne, "page_view", base, "/home");
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "content_impression",
                base.plusSeconds(1),
                "/home",
                "{\"category\":\"content\",\"action\":\"impression\",\"name\":\"home hero\","
                        + "\"data\":{\"contentName\":\"home hero\",\"contentPiece\":\"summer\","
                        + "\"contentTarget\":\"/summer?email=secret@example.test\"}}");
        insertRaw(
                site,
                visitorOne,
                sessionOne,
                "content_interaction",
                base.plusSeconds(2),
                "/home",
                "{\"category\":\"content\",\"action\":\"primary_cta\",\"name\":\"home hero\","
                        + "\"data\":{\"contentName\":\"home hero\",\"contentPiece\":\"summer\","
                        + "\"contentTarget\":\"/summer?email=secret@example.test\",\"interaction\":\"primary_cta\"}}");

        String visitorTwo = UUID.randomUUID().toString();
        String sessionTwo = UUID.randomUUID().toString();
        insertRaw(site, visitorTwo, sessionTwo, "page_view", base.plusSeconds(20), "/home");
        insertRaw(site, visitorTwo, sessionTwo, "page_view", base.plusSeconds(21), "/products");
        insertRaw(
                site,
                visitorTwo,
                sessionTwo,
                "content_impression",
                base.plusSeconds(22),
                "/home",
                "{\"category\":\"content\",\"action\":\"impression\",\"name\":\"home hero\","
                        + "\"data\":{\"contentName\":\"home hero\",\"contentPiece\":\"summer\","
                        + "\"contentTarget\":\"/summer?email=secret@example.test\"}}");
        insertRaw(
                site,
                visitorTwo,
                sessionTwo,
                "content_interaction",
                base.plusSeconds(23),
                "/home",
                "{\"category\":\"content\",\"action\":\"primary_cta\",\"name\":\"home hero\","
                        + "\"data\":{\"contentName\":\"home hero\",\"contentPiece\":\"summer\","
                        + "\"contentTarget\":\"/summer?email=secret@example.test\",\"interaction\":\"primary_cta\"}}");
        insertRaw(
                site,
                visitorTwo,
                sessionTwo,
                "content_impression",
                base.plusSeconds(24),
                "/home",
                "{\"category\":\"content\",\"action\":\"impression\",\"name\":\"footer promo\","
                        + "\"data\":{\"contentName\":\"footer promo\",\"contentPiece\":\"newsletter\"}}");
        factBuilder.rebuild(site, base.minusSeconds(5), base.plusSeconds(30));

        String report = "/api/v1/sites/" + siteId + "/analytics/content?from=" + reportDay + "&to=" + reportDay;
        given().header("Authorization", "Bearer " + owner.access())
                .get(report)
                .then()
                .statusCode(200)
                .body("impressions", is(3))
                .body("interactions", is(2))
                .body("uniqueVisitors", is(2))
                .body("sessions", is(2))
                .body("interactionRate", is(0.6666667f))
                .body("entries[0].name", is("home hero"))
                .body("entries[0].piece", is("summer"))
                .body("entries[0].target", is("/summer"))
                .body("entries[0].impressions", is(2))
                .body("entries[0].interactions", is(2))
                .body("entries[0].interactionRate", is(1f))
                .body("entries[1].name", is("footer promo"));

        String segmentId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Multi-page visitors\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"page_views\",\"operator\":\"at_least\",\"value\":\"2\"}]}")
                .post("/api/v1/sites/" + siteId + "/segments")
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .get(report + "&segmentId=" + segmentId)
                .then()
                .statusCode(200)
                .body("impressions", is(2))
                .body("interactions", is(1))
                .body("uniqueVisitors", is(1))
                .body("sessions", is(1))
                .body("entries[0].name", is("home hero"));

        Tokens outsider = register("content-outsider" + System.nanoTime() + "@example.test");
        given().header("Authorization", "Bearer " + outsider.access())
                .get(report)
                .then()
                .statusCode(404);
    }

    @Test
    void userFlowReportsOrderedPageTransitionsAndSessionExits() throws Exception {
        Tokens owner = register("user-flow" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String siteId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Journey site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");

        UUID site = UUID.fromString(siteId);
        String visitor = UUID.randomUUID().toString();
        String session = UUID.randomUUID().toString();
        LocalDate reportDay = LocalDate.now(ZoneId.of("UTC")).minusDays(1);
        Instant base = reportDay.atTime(23, 59, 50).toInstant(java.time.ZoneOffset.UTC);
        insertRaw(site, visitor, session, "page_view", base, "/landing");
        insertRaw(site, visitor, session, "page_view", base.plusSeconds(20), "/pricing");
        insertRaw(site, visitor, session, "page_view", base.plusSeconds(40), "/checkout");
        for (int index = 0; index < 21; index++) {
            String journeyVisitor = UUID.randomUUID().toString();
            String journeySession = UUID.randomUUID().toString();
            Instant journeyStart = base.minusSeconds(100L - index);
            insertRaw(site, journeyVisitor, journeySession, "page_view", journeyStart, "/landing");
            insertRaw(site, journeyVisitor, journeySession, "page_view", journeyStart.plusSeconds(5), "/pricing");
            insertRaw(site, journeyVisitor, journeySession, "page_view", journeyStart.plusSeconds(10), "/checkout");
        }
        String deepVisitor = UUID.randomUUID().toString();
        String deepSession = UUID.randomUUID().toString();
        for (int index = 1; index <= 6; index++) {
            insertRaw(
                    site, deepVisitor, deepSession, "page_view", base.minusSeconds(40L - index * 2L), "/deep/" + index);
        }
        factBuilder.rebuild(site, base.minusSeconds(200), base.plusSeconds(80));

        String today = reportDay.toString();
        List<java.util.Map<String, Object>> transitions = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/user-flow?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var landingTransition = transitions.stream()
                .filter(row -> "/landing".equals(row.get("sourcePath")))
                .findFirst()
                .orElseThrow();
        assertEquals(1, landingTransition.get("step"));
        assertEquals("/pricing", landingTransition.get("targetPath"));
        assertEquals(22, landingTransition.get("sessions"));
        var pricingTransition = transitions.stream()
                .filter(row -> "/pricing".equals(row.get("sourcePath")))
                .findFirst()
                .orElseThrow();
        assertEquals(2, pricingTransition.get("step"));
        assertEquals("/checkout", pricingTransition.get("targetPath"));
        var exitTransition = transitions.stream()
                .filter(row -> "/checkout".equals(row.get("sourcePath")))
                .findFirst()
                .orElseThrow();
        assertEquals(3, exitTransition.get("step"));
        assertNull(exitTransition.get("targetPath"));
        var fifthDeepTransition = transitions.stream()
                .filter(row -> "/deep/5".equals(row.get("sourcePath")))
                .findFirst()
                .orElseThrow();
        assertEquals(5, fifthDeepTransition.get("step"));
        assertEquals("/deep/6", fifthDeepTransition.get("targetPath"));
        assertTrue(transitions.stream().noneMatch(row -> Integer.valueOf(6).equals(row.get("step"))));

        var samples = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/user-flow/samples?from=" + today + "&to=" + today
                        + "&step=1&sourcePath=/landing&targetPath=/pricing")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath();
        assertNotNull(samples.get("totalSessions"), samples.get().toString());
        assertEquals(22, samples.getLong("totalSessions"));
        assertTrue(samples.getBoolean("hasMore"));
        assertNotNull(samples.getString("nextCursor"));
        assertEquals(20, samples.getList("sessions").size());
        assertEquals(3, samples.getList("sessions[0].pages").size());
        assertEquals("/landing", samples.getString("sessions[0].pages[0].path"));
        assertEquals("/pricing", samples.getString("sessions[0].pages[1].path"));
        assertFalse(samples.getMap("sessions[0]").containsKey("visitorId"));

        String nextCursor = samples.getString("nextCursor");
        var olderSamples = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/user-flow/samples?from=" + today + "&to=" + today
                        + "&step=1&sourcePath=/landing&targetPath=/pricing&cursor=" + nextCursor)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath();
        assertEquals(22, olderSamples.getLong("totalSessions"));
        assertFalse(olderSamples.getBoolean("hasMore"));
        assertNull(olderSamples.get("nextCursor"));
        assertEquals(2, olderSamples.getList("sessions").size());

        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/user-flow/samples?from=" + today + "&to=" + today
                        + "&step=1&sourcePath=/landing&targetPath=/pricing&cursor=not-a-cursor")
                .then()
                .statusCode(400);

        String longVisitSegment = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Long visits\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"page_views\",\"operator\":\"at_least\",\"value\":\"4\"}]}")
                .post("/api/v1/sites/" + siteId + "/segments")
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/user-flow/samples?from=" + today + "&to=" + today
                        + "&segmentId=" + longVisitSegment + "&step=1&sourcePath=/landing&targetPath=/pricing")
                .then()
                .statusCode(200)
                .body("totalSessions", is(0))
                .body("sessions.size()", is(0));

        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/user-flow/samples?from=" + today + "&to=" + today
                        + "&step=6&sourcePath=/landing&targetPath=/pricing")
                .then()
                .statusCode(400);

        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/user-flow/samples?from=" + today + "&to=" + today
                        + "&step=3&sourcePath=/checkout&exit=true")
                .then()
                .statusCode(200)
                .body("totalSessions", is(22))
                .body("sessions.size()", is(20))
                .body("sessions[0].pages.size()", is(3));
    }

    @Test
    void conversionAttributionAppliesModelsLookbackAndSavedSegmentToConversionSessions() throws Exception {
        Tokens owner = register("attribution" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String siteId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Attribution site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String goalId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Signup\",\"triggerType\":\"page_view\","
                        + "\"pathPattern\":\"/thanks\",\"pathMatchMode\":\"exact\",\"fixedValue\":100}")
                .post("/api/v1/sites/" + siteId + "/goals")
                .then()
                .statusCode(200)
                .extract()
                .path("id");

        UUID site = UUID.fromString(siteId);
        String visitor = UUID.randomUUID().toString();
        LocalDate conversionDay = LocalDate.now(ZoneId.of("UTC")).minusDays(1);
        Instant first = conversionDay.minusDays(5).atTime(10, 0).toInstant(java.time.ZoneOffset.UTC);
        Instant second = conversionDay.minusDays(2).atTime(10, 0).toInstant(java.time.ZoneOffset.UTC);
        Instant conversion = conversionDay.atTime(10, 0).toInstant(java.time.ZoneOffset.UTC);
        Instant outsideWindow = conversionDay.minusDays(45).atTime(10, 0).toInstant(java.time.ZoneOffset.UTC);
        insertAttributionPage(
                site, visitor, UUID.randomUUID().toString(), outsideWindow, "/old", "old.example", null, null, null);
        insertAttributionPage(
                site, visitor, UUID.randomUUID().toString(), first, "/landing", "facebook.com", null, null, null);
        insertAttributionPage(
                site, visitor, UUID.randomUUID().toString(), second, "/promo", null, "newsletter", "email", "spring");
        insertAttributionPage(
                site, visitor, UUID.randomUUID().toString(), conversion, "/thanks", null, null, null, null);
        String conversionSession = UUID.randomUUID().toString();
        insertRaw(site, visitor, conversionSession, "page_view", conversion.plusSeconds(1), "/thanks");
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "update raw_event set client_session_id=(select client_session_id from raw_event where site_id=? and client_visitor_id=? and page_path='/thanks' order by occurred_at limit 1) where site_id=? and client_visitor_id=? and client_session_id=?")) {
            statement.setObject(1, site);
            statement.setString(2, visitor);
            statement.setObject(3, site);
            statement.setString(4, visitor);
            statement.setString(5, conversionSession);
            statement.executeUpdate();
        }
        factBuilder.rebuild(site, first, conversion.plusSeconds(5));

        String reportPath = "/api/v1/sites/" + siteId + "/analytics/attribution?from=" + conversionDay + "&to="
                + conversionDay + "&lookbackDays=30&goalId=" + goalId;
        var firstTouch = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&model=first_touch")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath();
        assertEquals("first_touch", firstTouch.getString("model"));
        var firstRows = firstTouch.getList("rows", java.util.Map.class);
        assertEquals(1.0, attributionCredit(firstRows, "social"), 0.001);
        assertEquals(0.0, attributionCredit(firstRows, "campaign"), 0.001);

        var lastRows = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&model=last_touch")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList("rows", java.util.Map.class);
        assertEquals(1.0, attributionCredit(lastRows, "direct"), 0.001);

        var linearRows = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&model=linear")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList("rows", java.util.Map.class);
        assertFalse(linearRows.stream().anyMatch(row -> "referral".equals(row.get("channel"))));
        assertEquals(1.0 / 3.0, attributionCredit(linearRows, "social"), 0.001);
        assertEquals(1.0 / 3.0, attributionCredit(linearRows, "campaign"), 0.001);
        assertEquals(1.0 / 3.0, attributionCredit(linearRows, "direct"), 0.001);

        var positionRows = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&model=position_based")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList("rows", java.util.Map.class);
        assertEquals(0.4, attributionCredit(positionRows, "social"), 0.001);
        assertEquals(0.2, attributionCredit(positionRows, "campaign"), 0.001);
        assertEquals(0.4, attributionCredit(positionRows, "direct"), 0.001);

        var decayRows = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&model=time_decay")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList("rows", java.util.Map.class);
        assertTrue(attributionCredit(decayRows, "direct") > attributionCredit(decayRows, "campaign"));
        assertTrue(attributionCredit(decayRows, "campaign") > attributionCredit(decayRows, "social"));

        String matchingSegmentId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Signup conversions\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"entry_page\",\"operator\":\"equals\",\"value\":\"/thanks\"}]}")
                .post("/api/v1/sites/" + siteId + "/segments")
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&model=linear&segmentId=" + matchingSegmentId)
                .then()
                .statusCode(200)
                .body("attributedConversions", is(1.0f));
        String segmentId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"No signup conversions\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"entry_page\",\"operator\":\"equals\",\"value\":\"/never\"}]}")
                .post("/api/v1/sites/" + siteId + "/segments")
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&model=linear&segmentId=" + segmentId)
                .then()
                .statusCode(200)
                .body("rows.size()", is(0))
                .body("attributedConversions", is(0));

        given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&model=unsupported")
                .then()
                .statusCode(400);
    }

    @Test
    void cohortReportCalculatesWeeklyRetentionAndLeavesImmatureWeeksBlank() throws Exception {
        Tokens owner = register("cohorts" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String siteId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Cohort site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspaceId + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        UUID site = UUID.fromString(siteId);
        LocalDate cohortWeek = LocalDate.now(ZoneId.of("UTC"))
                .minusWeeks(12)
                .with(java.time.temporal.TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY));

        String returningVisitor = UUID.randomUUID().toString();
        insertRaw(
                site,
                returningVisitor,
                UUID.randomUUID().toString(),
                "page_view",
                cohortWeek.plusDays(1).atTime(12, 0).toInstant(java.time.ZoneOffset.UTC),
                "/cohort/a");
        insertRaw(
                site,
                returningVisitor,
                UUID.randomUUID().toString(),
                "page_view",
                cohortWeek.plusDays(8).atTime(12, 0).toInstant(java.time.ZoneOffset.UTC),
                "/return");
        String goalVisitor = UUID.randomUUID().toString();
        insertRaw(
                site,
                goalVisitor,
                UUID.randomUUID().toString(),
                "page_view",
                cohortWeek.plusDays(2).atTime(10, 0).toInstant(java.time.ZoneOffset.UTC),
                "/before-goal");
        insertRaw(
                site,
                goalVisitor,
                UUID.randomUUID().toString(),
                "page_view",
                cohortWeek.plusDays(2).atTime(12, 0).toInstant(java.time.ZoneOffset.UTC),
                "/cohort/b");
        insertRaw(
                site,
                UUID.randomUUID().toString(),
                UUID.randomUUID().toString(),
                "page_view",
                cohortWeek.plusDays(9).atTime(12, 0).toInstant(java.time.ZoneOffset.UTC),
                "/cohort/c");
        factBuilder.rebuild(
                site,
                cohortWeek.atStartOfDay(ZoneId.of("UTC")).toInstant(),
                cohortWeek.plusDays(14).atStartOfDay(ZoneId.of("UTC")).toInstant());

        String from = cohortWeek.toString();
        String to = cohortWeek.plusDays(13).toString();
        String reportPath = "/api/v1/sites/" + siteId + "/analytics/cohorts?from=" + from + "&to=" + to + "&weeks=4";
        List<java.util.Map<String, Object>> cells = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");

        var weekZero = cells.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(2, weekZero.get("cohortSize"));
        assertEquals(2, weekZero.get("retainedVisitors"));
        assertTrue(Boolean.TRUE.equals(weekZero.get("complete")));
        var returningWeek = cells.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(1).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(1, returningWeek.get("retainedVisitors"));
        assertEquals(0.5d, ((Number) returningWeek.get("retentionRate")).doubleValue());
        assertTrue(Boolean.TRUE.equals(returningWeek.get("complete")));
        var immatureWeek = cells.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(2).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(0, immatureWeek.get("retainedVisitors"));
        assertTrue(Boolean.FALSE.equals(immatureWeek.get("complete")));

        List<java.util.Map<String, Object>> visitCells = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&metric=visits")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var visitWeekZero = visitCells.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(3, visitWeekZero.get("visits"));
        var visitWeekOne = visitCells.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(1).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(1, visitWeekOne.get("visits"));

        String segmentId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"First page A\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"entry_page\",\"operator\":\"equals\",\"value\":\"/cohort/a\"}]}")
                .post("/api/v1/sites/" + siteId + "/segments")
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        List<java.util.Map<String, Object>> segmented = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&segmentId=" + segmentId)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        assertEquals(4, segmented.size());
        assertTrue(segmented.stream().allMatch(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod"))));
        assertTrue(segmented.stream().allMatch(cell -> Integer.valueOf(1).equals(cell.get("cohortSize"))));

        String goalId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Reached cohort B\",\"triggerType\":\"page_view\","
                        + "\"pathPattern\":\"/cohort/b\",\"pathMatchMode\":\"exact\",\"fixedValue\":15}")
                .post("/api/v1/sites/" + siteId + "/goals")
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Second cohort B value\",\"triggerType\":\"page_view\","
                        + "\"pathPattern\":\"/cohort/b\",\"pathMatchMode\":\"exact\",\"fixedValue\":2}")
                .post("/api/v1/sites/" + siteId + "/goals")
                .then()
                .statusCode(200);
        String goalCohortPath = reportPath + "&basis=goal_conversion&goalId=" + goalId;
        List<java.util.Map<String, Object>> goalCohorts = given().header("Authorization", "Bearer " + owner.access())
                .get(goalCohortPath)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        assertEquals(4, goalCohorts.size());
        var goalWeekZero = goalCohorts.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(1, goalWeekZero.get("cohortSize"));
        assertEquals(1, goalWeekZero.get("retainedVisitors"));
        List<java.util.Map<String, Object>> goalVisits = given().header("Authorization", "Bearer " + owner.access())
                .get(goalCohortPath + "&metric=visits")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var postConversionVisits = goalVisits.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(1, postConversionVisits.get("visits"));
        var goalWeekOne = goalCohorts.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(1).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(0, goalWeekOne.get("retainedVisitors"));

        List<java.util.Map<String, Object>> goalConversions = given().header(
                        "Authorization", "Bearer " + owner.access())
                .get(reportPath + "&metric=goal_conversions&metricGoalId=" + goalId)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var conversionWeekZero = goalConversions.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(1, conversionWeekZero.get("goalConversions"));
        assertEquals(1, conversionWeekZero.get("goalConvertedVisitors"));
        assertEquals(15.0d, ((Number) conversionWeekZero.get("goalValue")).doubleValue());
        var conversionWeekOne = goalConversions.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(1).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(0, conversionWeekOne.get("goalConversions"));
        List<java.util.Map<String, Object>> goalValueCells = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&metric=goal_value")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var summedGoalValue = goalValueCells.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(17.0d, ((Number) summedGoalValue.get("goalValue")).doubleValue());
        given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&metric=goal_conversions")
                .then()
                .statusCode(400);
        given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&metric=unknown")
                .then()
                .statusCode(400);

        given().header("Authorization", "Bearer " + owner.access())
                .get(goalCohortPath + "&segmentId=" + segmentId)
                .then()
                .statusCode(200)
                .body("size()", is(0));
        given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&basis=goal_conversion")
                .then()
                .statusCode(400);

        List<java.util.Map<String, Object>> daily = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&period=day&periods=14")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var dailyReturn = daily.stream()
                .filter(cell -> cohortWeek.plusDays(1).toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(7).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(1, dailyReturn.get("retainedVisitors"));
        assertTrue(Boolean.TRUE.equals(dailyReturn.get("complete")));

        List<java.util.Map<String, Object>> monthly = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&period=month&periods=3")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        LocalDate cohortMonth = cohortWeek.plusDays(1).withDayOfMonth(1);
        assertTrue(monthly.stream().anyMatch(cell -> cohortMonth.toString().equals(cell.get("cohortPeriod"))));

        List<java.util.Map<String, Object>> custom = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&period=custom&periodDays=14&periods=4")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var customZero = custom.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(3, customZero.get("cohortSize"));
        var customOne = custom.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(1).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertFalse(Boolean.TRUE.equals(customOne.get("complete")));
        List<java.util.Map<String, Object>> customVisits = given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&period=custom&periodDays=14&periods=4&metric=visits")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var customVisitZero = customVisits.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertTrue(((Number) customVisitZero.get("visits")).longValue() > 0);
        List<java.util.Map<String, Object>> customGoalValue = given().header(
                        "Authorization", "Bearer " + owner.access())
                .get(reportPath + "&period=custom&periodDays=14&periods=4&metric=goal_value")
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var customGoalValueZero = customGoalValue.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(17, ((Number) customGoalValueZero.get("goalValue")).intValue());
        List<java.util.Map<String, Object>> customConversions = given().header(
                        "Authorization", "Bearer " + owner.access())
                .get(reportPath + "&period=custom&periodDays=14&periods=4&metric=goal_conversions&metricGoalId="
                        + goalId)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        var customConversionZero = customConversions.stream()
                .filter(cell -> cohortWeek.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(1, customConversionZero.get("goalConversions"));
        assertEquals(1, customConversionZero.get("goalConvertedVisitors"));
        String yearRangeFrom = cohortWeek.minusYears(3).toString();
        String yearReportPath = "/api/v1/sites/" + siteId + "/analytics/cohorts?from=" + yearRangeFrom + "&to=" + to
                + "&period=year&periods=3";
        List<java.util.Map<String, Object>> yearly = given().header("Authorization", "Bearer " + owner.access())
                .get(yearReportPath)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList(".");
        LocalDate cohortYear = cohortWeek.plusDays(1).withDayOfYear(1);
        var yearZero = yearly.stream()
                .filter(cell -> cohortYear.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(0).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertEquals(3, yearZero.get("cohortSize"));
        assertTrue(Boolean.TRUE.equals(yearZero.get("complete")));
        var immatureYear = yearly.stream()
                .filter(cell -> cohortYear.toString().equals(cell.get("cohortPeriod")))
                .filter(cell -> Integer.valueOf(1).equals(cell.get("periodIndex")))
                .findFirst()
                .orElseThrow();
        assertFalse(Boolean.TRUE.equals(immatureYear.get("complete")));

        LocalDate today = LocalDate.now(ZoneId.of("UTC"));
        given().header("Authorization", "Bearer " + owner.access())
                .get(reportPath + "&period=custom&periodDays=366&periods=4")
                .then()
                .statusCode(400);
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + siteId + "/analytics/cohorts?from=" + today.minusDays(3660) + "&to=" + today
                        + "&period=year&periods=3")
                .then()
                .statusCode(400);
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
    void capturesMaskedDomAndRecordingChunksFromAnAllowedOrigin() {
        Tokens owner = register("recording" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        var created = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Recording\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract();
        String site = created.path("id");
        String trackingId = created.path("trackingId");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"host\":\"capture.example\",\"enabled\":true}")
                .post("/api/v1/sites/" + site + "/domains")
                .then()
                .statusCode(201);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(
                        "{\"enabled\":true,\"sampleRate\":100,\"rawRetentionDays\":30,\"aggregateRetentionDays\":180,\"autoSnapshotEnabled\":true,\"recordingEnabled\":true,\"recordingSampleRate\":100,\"recordingRetentionDays\":14}")
                .put("/api/v1/sites/" + site + "/heatmaps/config")
                .then()
                .statusCode(200)
                .body("recordingEnabled", is(true));

        String instance = UUID.randomUUID().toString();
        var snapshot = given().header("Origin", "https://capture.example")
                .contentType("application/json")
                .body(
                        "{\"protocolVersion\":1,\"instanceId\":\"" + instance
                                + "\",\"url\":\"https://capture.example/form?token=secret\",\"layoutVersion\":\"v1\",\"targetId\":\"page\",\"viewportWidth\":1200,\"viewportHeight\":800,\"contentWidth\":1200,\"contentHeight\":2400,\"events\":[{\"type\":2,\"timestamp\":1,\"data\":{}}]}")
                .post("/api/v1/collect/dom-snapshots/" + trackingId)
                .then()
                .statusCode(201)
                .body("captured", is(true))
                .extract();
        String variant = snapshot.path("variantId");
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site + "/heatmaps/dom-snapshots/" + variant)
                .then()
                .statusCode(200)
                .body("size()", is(1));

        String recording = UUID.randomUUID().toString();
        given().header("Origin", "https://capture.example")
                .contentType("application/json")
                .body(
                        "{\"protocolVersion\":1,\"recordingId\":\"" + recording
                                + "\",\"instanceId\":\"" + instance
                                + "\",\"sequence\":0,\"startedOffsetMs\":0,\"finalChunk\":true,\"url\":\"https://capture.example/form\",\"events\":[{\"type\":4,\"timestamp\":1,\"data\":{}}]}")
                .post("/api/v1/collect/recordings/" + trackingId)
                .then()
                .statusCode(202)
                .body("accepted", is(true));
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site + "/heatmaps/recordings/" + recording)
                .then()
                .statusCode(200)
                .body("size()", is(1))
                .body("[0].pageUrl", is("https://capture.example/form"));
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
        String day = LocalDate.now(ZoneId.of("UTC")).toString();
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
        insertAnalyticsRaw(siteId, "a", "a1", "page_view", dayOne, "/a", "www.google.com", null, null, null);
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
                "launch",
                "buy",
                "hero-card");
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
                .body("channel", hasItems("direct", "referral", "campaign", "search_engine"))
                .body("find { it.channel == 'campaign' }.term", is("buy"))
                .body("find { it.channel == 'campaign' }.content", is("hero-card"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"campaign_term\",\"metric\":\"sessions\",\"limit\":10}")
                .post(base + "/custom-report/query?from=2026-09-02&to=2026-09-03")
                .then()
                .statusCode(200)
                .body("rows.dimensionValue", hasItem("buy"));
        String campaignSegment = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Campaign term buy\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"campaign_term\",\"operator\":\"equals\",\"value\":\"buy\"}]}")
                .post("/api/v1/sites/" + site + "/segments")
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/traffic?from=2026-09-02&to=2026-09-03&segmentId=" + campaignSegment)
                .then()
                .statusCode(200)
                .body("size()", is(1))
                .body("channel", contains("campaign"))
                .body("term", contains("buy"))
                .body("content", contains("hero-card"));
        String searchSegment = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Google referrals\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"referrer\",\"operator\":\"equals\",\"value\":\"www.google.com\"}]}")
                .post("/api/v1/sites/" + site + "/segments")
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/traffic?from=2026-09-02&to=2026-09-03&segmentId=" + searchSegment)
                .then()
                .statusCode(200)
                .body("channel", contains("search_engine"))
                .body("source", contains("www.google.com"));
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/events?from=2026-09-02&to=2026-09-03")
                .then()
                .statusCode(200)
                .body("eventType", hasItems("page_view", "custom"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"campaign\",\"metric\":\"sessions\",\"limit\":10,"
                        + "\"matchMode\":\"all\",\"filters\":[{\"field\":\"source\","
                        + "\"operator\":\"equals\",\"value\":\"newsletter\"}]}")
                .post(base + "/custom-report/query?from=2026-09-02&to=2026-09-03")
                .then()
                .statusCode(200)
                .body("dimension", is("campaign"))
                .body("metric", is("sessions"))
                .body("rows[0].dimensionValue", is("launch"))
                .body("rows[0].metricValue", is(1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"browser; drop table analytics_session\",\"metric\":\"sessions\","
                        + "\"limit\":10}")
                .post(base + "/custom-report/query?from=2026-09-02&to=2026-09-03")
                .then()
                .statusCode(400);
        Tokens outsider = register("outsider" + System.nanoTime() + "@example.test");
        given().header("Authorization", "Bearer " + outsider.access())
                .get(base + "/overview")
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + outsider.access())
                .contentType("application/json")
                .body("{\"dimension\":\"unknown\",\"metric\":\"sessions\",\"limit\":10}")
                .post(base + "/custom-report/query")
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + owner.access())
                .get(base + "/overview?from=2026-09-04&to=2026-09-03")
                .then()
                .statusCode(400);
    }

    @Test
    void savesPrivateDashboardLayoutsAndPreservesDefaultView() {
        Tokens owner = register("dashboard" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Dashboards\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String path = "/api/v1/sites/" + site + "/dashboards";
        String layout = "{\"name\":\"Overview\",\"isDefault\":true,\"widgets\":["
                + "{\"id\":\"key-metrics\",\"type\":\"summary\",\"title\":\"Key metrics\"},"
                + "{\"id\":\"visits-trend\",\"type\":\"trend\",\"title\":\"Visits by day\","
                + "\"metric\":\"sessions\",\"chartType\":\"line\"},"
                + "{\"id\":\"custom-breakdown\",\"type\":\"custom_report\",\"title\":\"Campaign visits\","
                + "\"dimension\":\"campaign\",\"metric\":\"sessions\",\"limit\":10,"
                + "\"chartType\":\"bars\",\"matchMode\":\"all\",\"filters\":[{\"field\":\"source\","
                + "\"operator\":\"contains\",\"value\":\"newsletter\"}]}]}";
        String originalId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(layout)
                .post(path)
                .then()
                .statusCode(200)
                .body("name", is("Overview"))
                .body("isDefault", is(true))
                .body("widgets.size()", is(3))
                .body("widgets[1].metric", is("sessions"))
                .body("widgets[2].type", is("custom_report"))
                .body("widgets[2].filters[0].value", is("newsletter"))
                .extract()
                .path("id");

        String copyId = given().header("Authorization", "Bearer " + owner.access())
                .post(path + "/" + originalId + "/duplicate")
                .then()
                .statusCode(200)
                .body("name", is("Overview copy"))
                .body("isDefault", is(false))
                .extract()
                .path("id");

        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Overview updated\",\"isDefault\":false,\"widgets\":[]}")
                .put(path + "/" + originalId)
                .then()
                .statusCode(200)
                .body("name", is("Overview updated"))
                .body("isDefault", is(false));
        given().header("Authorization", "Bearer " + owner.access())
                .get(path)
                .then()
                .statusCode(200)
                .body("[0].id", is(copyId))
                .body("[0].isDefault", is(true));

        given().header("Authorization", "Bearer " + owner.access())
                .delete(path + "/" + copyId)
                .then()
                .statusCode(204);
        given().header("Authorization", "Bearer " + owner.access())
                .get(path)
                .then()
                .statusCode(200)
                .body("size()", is(1))
                .body("[0].id", is(originalId))
                .body("[0].isDefault", is(true));

        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Broken\",\"widgets\":[{\"id\":\"bad\","
                        + "\"type\":\"raw_json\",\"title\":\"Unsupported\"}]}")
                .post(path)
                .then()
                .statusCode(400);
        Tokens outsider = register("dashboard-outsider" + System.nanoTime() + "@example.test");
        given().header("Authorization", "Bearer " + outsider.access())
                .get(path)
                .then()
                .statusCode(404);
    }

    @Test
    void customDimensionsManageAndReportTrackedEventProperties() throws Exception {
        Tokens owner = register("dimension" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        var siteResponse = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Dimensions\",\"timezone\":\"Asia/Shanghai\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract();
        String site = siteResponse.path("id");
        String trackingId = siteResponse.path("trackingId");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"host\":\"example.com\",\"enabled\":true}")
                .post("/api/v1/sites/" + site + "/domains")
                .then()
                .statusCode(201);

        String dimensionsPath = "/api/v1/sites/" + site + "/custom-dimensions";
        String dimensionId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(
                        "{\"name\":\"Subscription plan\",\"key\":\"subscription_plan\",\"description\":\"Plan selected at signup\",\"enabled\":true}")
                .post(dimensionsPath)
                .then()
                .statusCode(200)
                .body("name", is("Subscription plan"))
                .body("key", is("subscription_plan"))
                .extract()
                .path("id");

        String visitor = UUID.randomUUID().toString();
        String session = UUID.randomUUID().toString();
        String starterVisitor = UUID.randomUUID().toString();
        String starterSession = UUID.randomUUID().toString();
        String now = Instant.now().toString();
        var siteLocalStart = Instant.parse(now).atZone(ZoneId.of("Asia/Shanghai"));
        String payload = "{\"schemaVersion\":1,\"siteId\":\"" + trackingId + "\",\"events\":["
                + "{\"eventId\":\"" + UUID.randomUUID() + "\",\"type\":\"product_interaction\",\"occurredAt\":\"" + now
                + "\",\"url\":\"https://example.com/pricing\",\"visitorId\":\"" + visitor + "\",\"sessionId\":\""
                + session
                + "\",\"properties\":{\"subscription_plan\":\"pro\"}},"
                + "{\"eventId\":\"" + UUID.randomUUID() + "\",\"type\":\"product_interaction\",\"occurredAt\":\"" + now
                + "\",\"url\":\"https://example.com/pricing\",\"visitorId\":\"" + visitor + "\",\"sessionId\":\""
                + session
                + "\",\"properties\":{\"subscription_plan\":\"pro\"}},"
                + "{\"eventId\":\"" + UUID.randomUUID() + "\",\"type\":\"product_interaction\",\"occurredAt\":\"" + now
                + "\",\"url\":\"https://example.com/starter\",\"visitorId\":\"" + starterVisitor
                + "\",\"sessionId\":\"" + starterSession
                + "\",\"properties\":{\"subscription_plan\":\"starter\"}},"
                + "{\"eventId\":\"" + UUID.randomUUID() + "\",\"type\":\"page_view\",\"occurredAt\":\"" + now
                + "\",\"url\":\"https://example.com/pricing\",\"visitorId\":\"" + visitor + "\",\"sessionId\":"
                + "\"" + session + "\"},"
                + "{\"eventId\":\"" + UUID.randomUUID() + "\",\"type\":\"page_view\",\"occurredAt\":\"" + now
                + "\",\"url\":\"https://example.com/starter\",\"visitorId\":\"" + starterVisitor
                + "\",\"sessionId\":\"" + starterSession + "\"}]}";
        given().contentType("application/json")
                .body(payload)
                .post("/api/v1/collect")
                .then()
                .statusCode(202);

        long deadline = System.currentTimeMillis() + 8_000;
        long count = 0;
        do {
            Thread.sleep(200);
            try (var connection = dataSource.getConnection();
                    var statement = connection.prepareStatement("select count(*) from raw_event where site_id=?")) {
                statement.setObject(1, UUID.fromString(site));
                try (var result = statement.executeQuery()) {
                    result.next();
                    count = result.getLong(1);
                }
            }
        } while (count < 5 && System.currentTimeMillis() < deadline);
        assertEquals(5, count);
        String nestedPayload =
                """
                {"schemaVersion":1,"siteId":"%s","events":[{"eventId":"%s","type":"nested_test","occurredAt":"%s",
                "url":"https://example.com/pricing","visitorId":"%s","sessionId":"%s",
                "properties":{"product":{"category":{"name":"software"}},"password":"do-not-list"}}]}
                """
                        .formatted(trackingId, UUID.randomUUID(), now, visitor, session);
        given().contentType("application/json")
                .body(nestedPayload)
                .post("/api/v1/collect")
                .then()
                .statusCode(202);
        deadline = System.currentTimeMillis() + 8_000;
        do {
            Thread.sleep(200);
            try (var connection = dataSource.getConnection();
                    var statement = connection.prepareStatement("select count(*) from raw_event where site_id=?")) {
                statement.setObject(1, UUID.fromString(site));
                try (var result = statement.executeQuery()) {
                    result.next();
                    count = result.getLong(1);
                }
            }
        } while (count < 6 && System.currentTimeMillis() < deadline);
        assertEquals(6, count);
        Instant occurredAt = Instant.parse(now);
        factBuilder.rebuild(UUID.fromString(site), occurredAt.minusSeconds(1), occurredAt.plusSeconds(1));
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "update analytics_session set duration_ms=45000 where site_id=? and client_session_id=?")) {
            statement.setObject(1, UUID.fromString(site));
            statement.setString(2, session);
            assertEquals(1, statement.executeUpdate());
        }

        String today = siteLocalStart.toLocalDate().toString();
        String customDimension = "custom:" + dimensionId;
        String propertyId = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site + "/analytics/custom-report/event-properties?from=" + today + "&to="
                        + today)
                .then()
                .statusCode(200)
                .body("find { it.label == 'product › category › name' }.eventCount", is(1))
                .body("find { it.label == 'password' }", nullValue())
                .extract()
                .path("find { it.label == 'product › category › name' }.id");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"" + propertyId
                        + "\",\"metric\":\"events\",\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("customDimensionName", is("product › category › name"))
                .body("rows.dimensionValue", contains("software"))
                .body("rows.metricValue", contains(1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"" + propertyId
                        + "\",\"secondaryDimension\":\"event_type\",\"metric\":\"events\","
                        + "\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body(
                        "rows.find { it.dimensionValue == 'software' && it.secondaryDimensionValue == 'nested_test' }.metricValue",
                        is(1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Nested property report\",\"widgets\":[{\"id\":\"nested\","
                        + "\"type\":\"custom_report\",\"title\":\"Events by product category\",\"dimension\":\""
                        + propertyId + "\",\"metric\":\"events\",\"limit\":5,\"chartType\":\"table\"}]}")
                .post("/api/v1/sites/" + site + "/dashboards")
                .then()
                .statusCode(200)
                .body("widgets[0].dimension", is(propertyId));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"" + customDimension
                        + "\",\"metric\":\"sessions\",\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("customDimensionName", is("Subscription plan"))
                .body("rows.dimensionValue", contains("pro", "starter"))
                .body("rows.metricValue", contains(1.0f, 1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"" + customDimension
                        + "\",\"metric\":\"events\",\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("customDimensionName", is("Subscription plan"))
                .body("rows.dimensionValue", contains("pro", "starter"))
                .body("rows.metricValue", contains(2.0f, 1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"" + customDimension
                        + "\",\"metric\":\"formula\",\"formula\":{"
                        + "\"name\":\"Events per visit\",\"leftMetric\":\"events\","
                        + "\"operator\":\"divide\",\"rightMetric\":\"sessions\",\"format\":\"number\"},"
                        + "\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("formulaName", is("Events per visit"))
                .body("rows.dimensionValue", contains("pro", "starter"))
                .body("rows.metricValue", contains(2.0f, 1.0f));

        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"metric\":\"events\",\"limit\":10,"
                        + "\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("customDimensionName", nullValue())
                .body("rows.dimensionValue", contains("product_interaction", "page_view", "nested_test"))
                .body("rows.metricValue", contains(3.0f, 2.0f, 1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"secondaryDimension\":\"" + customDimension
                        + "\",\"metric\":\"events\",\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("customDimensionName", nullValue())
                .body("secondaryCustomDimensionName", is("Subscription plan"))
                .body(
                        "rows.find { it.dimensionValue == 'product_interaction' && it.secondaryDimensionValue == 'pro' }.metricValue",
                        is(2.0f))
                .body(
                        "rows.find { it.dimensionValue == 'page_view' && it.secondaryDimensionValue == 'Unknown' }.metricValue",
                        is(2.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"secondaryDimension\":\"" + customDimension
                        + "\",\"metric\":\"formula\",\"formula\":{"
                        + "\"name\":\"Events per visit\",\"leftMetric\":\"events\","
                        + "\"operator\":\"divide\",\"rightMetric\":\"sessions\",\"format\":\"number\"},"
                        + "\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body(
                        "rows.find { it.dimensionValue == 'product_interaction' && it.secondaryDimensionValue == 'pro' }.metricValue",
                        is(2.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"" + customDimension
                        + "\",\"secondaryDimension\":\"entry_page\",\"metric\":\"sessions\","
                        + "\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("customDimensionName", is("Subscription plan"))
                .body(
                        "rows.find { it.dimensionValue == 'pro' && it.secondaryDimensionValue == '/pricing' }.metricValue",
                        is(1.0f))
                .body(
                        "rows.find { it.dimensionValue == 'Unknown' && it.secondaryDimensionValue == '/pricing' }.metricValue",
                        is(1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"metric\":\"sessions\",\"limit\":10,"
                        + "\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("rows.dimensionValue", contains("page_view", "product_interaction", "nested_test"))
                .body("rows.metricValue", contains(2.0f, 2.0f, 1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"metric\":\"formula\",\"formula\":{"
                        + "\"name\":\"Events per visit\",\"leftMetric\":\"events\","
                        + "\"operator\":\"divide\",\"rightMetric\":\"sessions\",\"format\":\"percent\"},"
                        + "\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("formulaName", is("Events per visit"))
                .body("rows.dimensionValue", hasItems("product_interaction", "page_view", "nested_test"))
                .body("rows.find { it.dimensionValue == 'product_interaction' }.metricValue", is(150.0f))
                .body("rows.find { it.dimensionValue == 'nested_test' }.metricValue", is(100.0f))
                .body("rows.find { it.dimensionValue == 'page_view' }.metricValue", is(100.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"metric\":\"formula\",\"formula\":{"
                        + "\"name\":\"Unsafe\",\"leftMetric\":\"events\",\"operator\":\"/; drop table\","
                        + "\"rightMetric\":\"sessions\",\"format\":\"number\"},"
                        + "\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(400);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"entry_page\",\"secondaryDimension\":\"exit_page\","
                        + "\"metric\":\"sessions\",\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("secondaryDimension", is("exit_page"))
                .body("rows.dimensionValue", contains("/pricing", "/starter"))
                .body("rows.secondaryDimensionValue", contains("/pricing", "/starter"))
                .body("rows.metricValue", contains(1.0f, 1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"secondaryDimension\":\"browser\","
                        + "\"metric\":\"sessions\",\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("secondaryDimension", is("browser"))
                .body("rows.dimensionValue", hasItem("page_view"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"secondaryDimension\":\"" + customDimension
                        + "\",\"tertiaryDimension\":\"entry_page\",\"metric\":\"events\","
                        + "\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("dimension", is("event_type"))
                .body("tertiaryDimension", is("entry_page"))
                .body("tertiaryCustomDimensionName", nullValue())
                .body(
                        "rows.find { it.dimensionValue == 'product_interaction' && it.secondaryDimensionValue == 'pro' && it.tertiaryDimensionValue == '/pricing' }.metricValue",
                        is(2.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"entry_page\",\"secondaryDimension\":\"exit_page\","
                        + "\"tertiaryDimension\":\"visitor_type\",\"metric\":\"sessions\","
                        + "\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("tertiaryDimension", is("visitor_type"))
                .body("rows.size()", is(2))
                .body("rows.tertiaryDimensionValue", everyItem(is("new")));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"entry_page\",\"secondaryDimension\":\"exit_page\","
                        + "\"tertiaryDimension\":\"visitor_type\",\"quaternaryDimension\":\"browser\","
                        + "\"metric\":\"sessions\",\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("quaternaryDimension", is("browser"))
                .body("rows.size()", is(2))
                .body("rows.quaternaryDimensionValue", everyItem(is("Unknown")));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"secondaryDimension\":\"" + customDimension
                        + "\",\"tertiaryDimension\":\"entry_page\",\"quaternaryDimension\":\"browser\","
                        + "\"metric\":\"events\",\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("quaternaryDimension", is("browser"))
                .body("secondaryCustomDimensionName", is("Subscription plan"))
                .body(
                        "rows.find { it.dimensionValue == 'product_interaction' && it.secondaryDimensionValue == 'pro' && it.tertiaryDimensionValue == '/pricing' && it.quaternaryDimensionValue == 'Unknown' }.metricValue",
                        is(2.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"secondaryDimension\":\"browser\","
                        + "\"tertiaryDimension\":\"event_type\",\"metric\":\"sessions\","
                        + "\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today)
                .then()
                .statusCode(400);

        String dashboardPath = "/api/v1/sites/" + site + "/dashboards";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Plan breakdown\",\"widgets\":[{\"id\":\"plans\","
                        + "\"type\":\"custom_report\",\"title\":\"Visits by plan\",\"dimension\":\""
                        + customDimension
                        + "\",\"metric\":\"sessions\",\"limit\":10,\"chartType\":\"table\"},"
                        + "{\"id\":\"calculated\",\"type\":\"custom_report\","
                        + "\"title\":\"Events per visit\",\"dimension\":\"" + customDimension
                        + "\",\"metric\":\"formula\",\"formula\":{"
                        + "\"name\":\"Events per visit\",\"leftMetric\":\"events\","
                        + "\"operator\":\"divide\",\"rightMetric\":\"sessions\",\"format\":\"number\"},"
                        + "\"limit\":10,\"chartType\":\"table\"},"
                        + "{\"id\":\"event-types\",\"type\":\"custom_report\","
                        + "\"title\":\"Events by type\",\"dimension\":\"event_type\","
                        + "\"metric\":\"events\",\"limit\":10,\"chartType\":\"table\"},"
                        + "{\"id\":\"paths\",\"type\":\"custom_report\","
                        + "\"title\":\"Entry and exit page\",\"dimension\":\"entry_page\","
                        + "\"secondaryDimension\":\"exit_page\",\"metric\":\"sessions\","
                        + "\"limit\":10,\"chartType\":\"table\"},"
                        + "{\"id\":\"event-custom\",\"type\":\"custom_report\","
                        + "\"title\":\"Event plans\",\"dimension\":\"event_type\","
                        + "\"secondaryDimension\":\"" + customDimension
                        + "\",\"metric\":\"events\",\"limit\":10,\"chartType\":\"table\"},"
                        + "{\"id\":\"three\",\"type\":\"custom_report\","
                        + "\"title\":\"Three dimensions\",\"dimension\":\"event_type\","
                        + "\"secondaryDimension\":\"browser\",\"tertiaryDimension\":\"country\","
                        + "\"metric\":\"sessions\",\"limit\":10,\"chartType\":\"table\"},"
                        + "{\"id\":\"four\",\"type\":\"custom_report\","
                        + "\"title\":\"Four dimensions\",\"dimension\":\"event_type\","
                        + "\"secondaryDimension\":\"browser\",\"tertiaryDimension\":\"country\","
                        + "\"quaternaryDimension\":\"device_type\",\"metric\":\"sessions\","
                        + "\"limit\":10,\"chartType\":\"table\"}]}")
                .post(dashboardPath)
                .then()
                .statusCode(200)
                .body("widgets[0].dimension", is(customDimension))
                .body("widgets[1].formula.name", is("Events per visit"))
                .body("widgets[2].dimension", is("event_type"))
                .body("widgets[3].secondaryDimension", is("exit_page"))
                .body("widgets[4].secondaryDimension", is(customDimension))
                .body("widgets[5].tertiaryDimension", is("country"))
                .body("widgets[6].quaternaryDimension", is("device_type"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Duplicate pivot\",\"widgets\":[{\"id\":\"bad\","
                        + "\"type\":\"custom_report\",\"title\":\"Bad report\","
                        + "\"dimension\":\"event_type\",\"secondaryDimension\":\"browser\","
                        + "\"tertiaryDimension\":\"event_type\",\"metric\":\"sessions\","
                        + "\"limit\":10,\"chartType\":\"table\"}]}")
                .post(dashboardPath)
                .then()
                .statusCode(400);

        given().header("Authorization", "Bearer " + owner.access())
                .get(dimensionsPath + "/" + dimensionId + "/report?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("value", contains("pro", "starter"))
                .body("events", contains(2, 1))
                .body("sessions", contains(1, 1))
                .body("visitors", contains(1, 1));

        String segmentsPath = "/api/v1/sites/" + site + "/segments";
        String segmentDraft = "{\"name\":\"Pro plan visitors\",\"description\":\"Visitors who used the pro plan\","
                + "\"matchMode\":\"all\",\"enabled\":true,\"rules\":[{\"field\":\"custom_property\","
                + "\"operator\":\"equals\",\"value\":\"pro\",\"dimensionKey\":\"subscription_plan\"},"
                + "{\"field\":\"page_views\",\"operator\":\"at_least\",\"value\":\"1\"},"
                + "{\"field\":\"event_count\",\"operator\":\"at_least\",\"value\":\"4\"},"
                + "{\"field\":\"visit_duration\",\"operator\":\"at_least\",\"value\":\"30\"}]}";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(segmentDraft)
                .post(segmentsPath + "/preview?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("sessions", is(1))
                .body("visitors", is(1));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Five events\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"event_count\",\"operator\":\"at_least\",\"value\":\"5\"}]}")
                .post(segmentsPath + "/preview?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("sessions", is(0));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Long visits\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"visit_duration\",\"operator\":\"at_least\",\"value\":\"46\"}]}")
                .post(segmentsPath + "/preview?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("sessions", is(0));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Too long\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"visit_duration\",\"operator\":\"at_least\",\"value\":\"86401\"}]}")
                .post(segmentsPath + "/preview?from=" + today + "&to=" + today)
                .then()
                .statusCode(400);
        String segmentId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(segmentDraft)
                .post(segmentsPath)
                .then()
                .statusCode(200)
                .body("name", is("Pro plan visitors"))
                .extract()
                .path("id");
        String visitorInterestPath =
                "/api/v1/sites/" + site + "/analytics/visitor-interest?from=" + today + "&to=" + today;
        given().header("Authorization", "Bearer " + owner.access())
                .get(visitorInterestPath)
                .then()
                .statusCode(200)
                .body("visitors", is(2))
                .body("sessions", is(2))
                .body("pageViews", is(2))
                .body("frequency.find { it.visits == '1' }.visitors", is(2))
                .body("frequency.find { it.visits == '1' }.sessions", is(2))
                .body("pageViewsPerSession.find { it.band == '1' }.sessions", is(2))
                .body("eventsPerSession.find { it.band == '1–2' }.sessions", is(1))
                .body("eventsPerSession.find { it.band == '3–5' }.sessions", is(1))
                .body("durationPerSession.find { it.band == '<10s' }.sessions", is(1))
                .body("durationPerSession.find { it.band == '30–<60s' }.sessions", is(1));
        given().header("Authorization", "Bearer " + owner.access())
                .get(visitorInterestPath + "&segmentId=" + segmentId)
                .then()
                .statusCode(200)
                .body("visitors", is(1))
                .body("sessions", is(1))
                .body("eventsPerSession.find { it.band == '3–5' }.sessions", is(1))
                .body("durationPerSession.find { it.band == '30–<60s' }.sessions", is(1));
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site + "/analytics/visit-time?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("size()", is(1))
                .body("[0].dayOfWeek", is(siteLocalStart.getDayOfWeek().getValue() - 1))
                .body("[0].hour", is(siteLocalStart.getHour()))
                .body("[0].sessions", is(2));
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site + "/analytics/visit-time?from=" + today + "&to=" + today + "&segmentId="
                        + segmentId)
                .then()
                .statusCode(200)
                .body("size()", is(1))
                .body("[0].sessions", is(1));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"event_type\",\"metric\":\"sessions\",\"limit\":10,"
                        + "\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today
                        + "&segmentId=" + segmentId)
                .then()
                .statusCode(200)
                .body("rows.dimensionValue", hasItems("page_view", "product_interaction", "nested_test"))
                .body("rows.metricValue", contains(1.0f, 1.0f, 1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"dimension\":\"" + customDimension
                        + "\",\"metric\":\"sessions\",\"limit\":10,\"matchMode\":\"all\",\"filters\":[]}")
                .post("/api/v1/sites/" + site + "/analytics/custom-report/query?from=" + today + "&to=" + today
                        + "&segmentId=" + segmentId)
                .then()
                .statusCode(200)
                .body("customDimensionName", is("Subscription plan"))
                .body("rows.size()", is(1))
                .body("rows[0].dimensionValue", is("pro"))
                .body("rows[0].metricValue", is(1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .get(segmentsPath)
                .then()
                .statusCode(200)
                .body("name", hasItem("Pro plan visitors"));
        given().header("Authorization", "Bearer " + owner.access())
                .get(segmentsPath + "/" + segmentId + "/preview?from=" + today + "&to=" + today)
                .then()
                .statusCode(200)
                .body("sessions", is(1))
                .body("visitors", is(1));
        String analyticsPath = "/api/v1/sites/" + site + "/analytics";
        String filteredPeriod = "?from=" + today + "&to=" + today + "&segmentId=" + segmentId;
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/page-titles" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("path", contains("/pricing"))
                .body("pageViews", contains(1));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/entry-exit" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("flow", contains("entry", "exit"))
                .body("sessions", contains(1, 1));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Product interaction\",\"triggerType\":\"event\","
                        + "\"eventType\":\"product_interaction\",\"fixedValue\":5}")
                .post("/api/v1/sites/" + site + "/goals")
                .then()
                .statusCode(200);
        given().header("Authorization", "Bearer " + owner.access())
                .get(dimensionsPath + "/" + dimensionId + "/report" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("value", contains("pro"))
                .body("events", contains(2))
                .body("sessions", contains(1))
                .body("visitors", contains(1));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/overview" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("pageViews", is(1))
                .body("uniqueVisitors", is(1))
                .body("sessions", is(1));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/timeseries" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("pageViews", hasItem(1))
                .body("sessions", hasItem(1));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/pages" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("path", contains("/pricing"))
                .body("pageViews", contains(1));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/traffic" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("channel", contains("direct"))
                .body("sessions", contains(1));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/events" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("eventType", hasItems("product_interaction", "page_view"))
                .body("count", hasItems(2, 1));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/visitors" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("uniqueVisitors", is(1))
                .body("sessions", is(1))
                .body("newSessions", is(1));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/visitor-log" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("visitorId", contains(visitor));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/visitors/" + visitor + filteredPeriod)
                .then()
                .statusCode(200)
                .body("visitorId", is(visitor))
                .body("lifetimeSessions", is(1))
                .body("rangeSessions", is(1))
                .body("rangePageViews", is(1))
                .body("sessions.size()", is(1))
                .body("sessions[0].visitorType", is("new"))
                .body("sessions[0].entryPage", is("/pricing"))
                .body("actions.size()", is(4))
                .body("actions.eventType", hasItems("page_view", "product_interaction"));
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/visitors/not-a-real-visitor" + filteredPeriod)
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + owner.access())
                .get(analyticsPath + "/goals" + filteredPeriod)
                .then()
                .statusCode(200)
                .body("name", contains("Product interaction"))
                .body("count", contains(2))
                .body("convertedSessions", contains(1))
                .body("value", contains(10.0f))
                .body("conversionRate", contains(1.0f));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Pro plan visitors\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"visitor_type\",\"operator\":\"contains\",\"value\":\"new\"}]}")
                .post(segmentsPath)
                .then()
                .statusCode(400);

        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Invalid key\",\"key\":\"Subscription Plan\",\"enabled\":true}")
                .post(dimensionsPath)
                .then()
                .statusCode(400);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Subscription plan\",\"key\":\"plan\",\"enabled\":true}")
                .put(dimensionsPath + "/" + dimensionId)
                .then()
                .statusCode(400);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Duplicate key\",\"key\":\"subscription_plan\",\"enabled\":true}")
                .post(dimensionsPath)
                .then()
                .statusCode(409);
    }

    @Test
    void configuredGoalsReportConversionsValuesAndRates() throws Exception {
        Tokens owner = register("goal" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Goals\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String goalPath = "/api/v1/sites/" + site + "/goals";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(
                        "{\"name\":\"Signup completed\",\"triggerType\":\"event\",\"eventType\":\"goal\",\"eventName\":\"signup\",\"fixedValue\":12.5}")
                .post(goalPath)
                .then()
                .statusCode(200)
                .body("name", is("Signup completed"))
                .body("fixedValue", is(12.5f));
        UUID siteId = UUID.fromString(site);
        Instant occurred = Instant.parse("2026-09-04T12:00:00Z");
        insertRaw(siteId, "visitor-goal", "session-goal", "goal", occurred, "/signup");
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement(
                        "update raw_event set event_data='{\"name\":\"signup\"}'::jsonb where site_id=?")) {
            p.setObject(1, siteId);
            p.executeUpdate();
        }
        aggregation.rebuild(siteId, LocalDate.of(2026, 9, 4), LocalDate.of(2026, 9, 4));
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site + "/analytics/goals?from=2026-09-04&to=2026-09-04")
                .then()
                .statusCode(200)
                .body("name", contains("Signup completed"))
                .body("count", contains(1))
                .body("convertedSessions", contains(1))
                .body("value", contains(12.5f))
                .body("conversionRate", contains(1.0f));
    }

    @Test
    void createsAndReportsOrderedFunnel() throws Exception {
        Tokens owner = register("funnel" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Funnels\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String path = "/api/v1/sites/" + site + "/funnels";
        String body = "{\"name\":\"Signup funnel\",\"steps\":["
                + "{\"name\":\"Landing\",\"type\":\"page_view\",\"path\":\"/landing\"},"
                + "{\"name\":\"Signup\",\"type\":\"event\",\"eventType\":\"signup\"}]}";
        String funnel = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(body)
                .post(path)
                .then()
                .statusCode(200)
                .body("steps.size()", is(2))
                .extract()
                .path("id");
        UUID siteId = UUID.fromString(site);
        Instant occurred = Instant.parse("2026-09-01T12:00:00Z");
        insertRaw(siteId, "funnel-complete", "funnel-complete", "page_view", occurred, "/landing");
        insertRaw(siteId, "funnel-complete", "funnel-complete", "signup", occurred.plusSeconds(1), "/signup");
        insertRaw(siteId, "funnel-drop", "funnel-drop", "page_view", occurred.plusSeconds(2), "/landing");
        given().header("Authorization", "Bearer " + owner.access())
                .get(path + "/" + funnel + "/report?from=2026-09-01&to=2026-09-02")
                .then()
                .statusCode(200)
                .body("name", is("Signup funnel"))
                .body("steps.size()", is(2))
                .body("steps[0].sessions", is(2))
                .body("steps[1].sessions", is(1))
                .body("steps[1].dropOff", is(1))
                .body("steps[1].dropOffRate", is(0.5f));
    }

    @Test
    void createsAndReportsExperimentVariants() {
        Tokens owner = register("experiment" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Experiments\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String path = "/api/v1/sites/" + site + "/experiments";
        String id = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Hero\",\"variants\":[\"control\",\"new_copy\"],"
                        + "\"targeting\":{\"pathPrefixes\":[\"/pricing\"],\"deviceTypes\":[\"desktop\"]}}")
                .post(path)
                .then()
                .statusCode(200)
                .body("variants", contains("control", "new_copy"))
                .body("targeting.pathPrefixes", contains("/pricing"))
                .body("targeting.deviceTypes", contains("desktop"))
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Invalid target\",\"variants\":[\"control\",\"variant\"],"
                        + "\"targeting\":{\"pathPrefixes\":[\"pricing?coupon=secret\"]}}")
                .post(path)
                .then()
                .statusCode(400);
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Hero\",\"variants\":[\"control\",\"new_copy\"]}")
                .put(path + "/" + id)
                .then()
                .statusCode(200)
                .body("targeting.pathPrefixes", contains("/pricing"))
                .body("targeting.deviceTypes", contains("desktop"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"host\":\"experiment.example.test\",\"allowSubdomains\":false,\"enabled\":true}")
                .post("/api/v1/sites/" + site + "/domains")
                .then()
                .statusCode(201);
        String trackingId = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site)
                .then()
                .statusCode(200)
                .extract()
                .path("trackingId");
        given().header("Origin", "https://experiment.example.test")
                .get("/api/v1/experiments/" + trackingId + "/definitions")
                .then()
                .statusCode(200)
                .body("[0].name", is("Hero"))
                .body("[0].variants", contains("control", "new_copy"))
                .body("[0].targeting.pathPrefixes", contains("/pricing"))
                .body("[0].targeting.deviceTypes", contains("desktop"));
        given().header("Authorization", "Bearer " + owner.access())
                .get(path + "/" + id + "/report?from=2026-09-01&to=2026-09-02")
                .then()
                .statusCode(200)
                .body("variants.size()", is(2))
                .body("variants.exposures", contains(0, 0));
    }

    @Test
    void experimentLifecycleLocksSetupAfterExposureAndArchivesBeforeDeletion() throws Exception {
        Tokens owner = register("experiment-lifecycle" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Lifecycle site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String path = "/api/v1/sites/" + site + "/experiments";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"host\":\"lifecycle.example.test\",\"allowSubdomains\":false,\"enabled\":true}")
                .post("/api/v1/sites/" + site + "/domains")
                .then()
                .statusCode(201);
        String draft = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Checkout experiment\",\"status\":\"draft\","
                        + "\"allocationGroup\":\"checkout\",\"variants\":[\"control\",\"variant\"]}")
                .post(path)
                .then()
                .statusCode(200)
                .body("status", is("draft"))
                .body("enabled", is(false))
                .body("allocationGroup", is("checkout"))
                .body("configurationLocked", is(false))
                .extract()
                .path("id");

        String deniedBody = "{\"name\":\"Checkout experiment\",\"status\":\"paused\","
                + "\"enabled\":false,\"allocationGroup\":\"checkout\","
                + "\"variants\":[\"control\",\"variant\"]}";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(deniedBody)
                .put(path + "/" + draft)
                .then()
                .statusCode(409)
                .body("code", is("INVALID_EXPERIMENT_TRANSITION"));

        String trackingId = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site)
                .then()
                .statusCode(200)
                .extract()
                .path("trackingId");
        String publicPath = "/api/v1/experiments/" + trackingId + "/definitions";
        given().header("Origin", "https://lifecycle.example.test")
                .get(publicPath)
                .then()
                .statusCode(200)
                .body("size()", is(0));

        String startBody = "{\"name\":\"Checkout experiment\",\"status\":\"running\","
                + "\"enabled\":true,\"allocationGroup\":\"checkout\","
                + "\"variants\":[\"control\",\"variant\"]}";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(startBody)
                .put(path + "/" + draft)
                .then()
                .statusCode(200)
                .body("status", is("running"));
        given().header("Origin", "https://lifecycle.example.test")
                .get(publicPath)
                .then()
                .statusCode(200)
                .body("[0].name", is("Checkout experiment"));

        UUID siteId = UUID.fromString(site);
        insertRaw(
                siteId,
                "lifecycle-visitor",
                "lifecycle-session",
                "experiment_exposure",
                Instant.parse("2026-09-18T12:00:00Z"),
                "/checkout",
                "{\"action\":\"Checkout experiment\",\"name\":\"control\"}");
        given().header("Authorization", "Bearer " + owner.access())
                .get(path)
                .then()
                .statusCode(200)
                .body("find { it.id == '" + draft + "' }.configurationLocked", is(true));

        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Checkout experiment\",\"status\":\"running\","
                        + "\"enabled\":true,\"allocationGroup\":\"checkout\","
                        + "\"variants\":[\"control\",\"new_variant\"]}")
                .put(path + "/" + draft)
                .then()
                .statusCode(409)
                .body("code", is("EXPERIMENT_CONFIGURATION_LOCKED"));

        String pausedBody = "{\"name\":\"Checkout experiment\",\"status\":\"paused\","
                + "\"enabled\":false,\"allocationGroup\":\"checkout\","
                + "\"variants\":[\"control\",\"variant\"]}";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(pausedBody)
                .put(path + "/" + draft)
                .then()
                .statusCode(200)
                .body("status", is("paused"))
                .body("configurationLocked", is(true));
        given().header("Origin", "https://lifecycle.example.test")
                .get(publicPath)
                .then()
                .statusCode(200)
                .body("size()", is(0));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Checkout experiment\",\"status\":\"completed\","
                        + "\"enabled\":false,\"allocationGroup\":\"checkout\","
                        + "\"variants\":[\"control\",\"variant\"]}")
                .put(path + "/" + draft)
                .then()
                .statusCode(200)
                .body("status", is("completed"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(startBody)
                .put(path + "/" + draft)
                .then()
                .statusCode(409)
                .body("code", is("INVALID_EXPERIMENT_TRANSITION"));
        given().header("Authorization", "Bearer " + owner.access())
                .delete(path + "/" + draft)
                .then()
                .statusCode(409)
                .body("code", is("ARCHIVE_EXPERIMENT_BEFORE_DELETE"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Checkout experiment\",\"status\":\"archived\","
                        + "\"enabled\":false,\"allocationGroup\":\"checkout\","
                        + "\"variants\":[\"control\",\"variant\"]}")
                .put(path + "/" + draft)
                .then()
                .statusCode(200)
                .body("status", is("archived"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(startBody)
                .put(path + "/" + draft)
                .then()
                .statusCode(409)
                .body("code", is("EXPERIMENT_ARCHIVED"));
        given().header("Authorization", "Bearer " + owner.access())
                .delete(path + "/" + draft)
                .then()
                .statusCode(204);
    }

    @Test
    void publicExperimentDefinitionsReturnOneStableCandidatePerAllocationLayer() {
        Tokens owner = register("experiment-layers" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Layer site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String path = "/api/v1/sites/" + site + "/experiments";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"host\":\"layers.example.test\",\"allowSubdomains\":false,\"enabled\":true}")
                .post("/api/v1/sites/" + site + "/domains")
                .then()
                .statusCode(201);
        for (String definition : List.of(
                "{\"name\":\"Checkout copy\",\"allocationGroup\":\"checkout\",\"variants\":[\"control\",\"copy\"]}",
                "{\"name\":\"Checkout layout\",\"allocationGroup\":\"checkout\",\"variants\":[\"control\",\"layout\"]}",
                "{\"name\":\"Independent banner\",\"variants\":[\"control\",\"banner\"]}")) {
            given().header("Authorization", "Bearer " + owner.access())
                    .contentType("application/json")
                    .body(definition)
                    .post(path)
                    .then()
                    .statusCode(200);
        }
        String trackingId = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site)
                .then()
                .statusCode(200)
                .extract()
                .path("trackingId");
        String publicPath = "/api/v1/experiments/" + trackingId + "/definitions?visitorId=" + UUID.randomUUID();
        List<String> first = given().header("Origin", "https://layers.example.test")
                .get(publicPath)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList("name");
        List<String> repeated = given().header("Origin", "https://layers.example.test")
                .get(publicPath)
                .then()
                .statusCode(200)
                .extract()
                .jsonPath()
                .getList("name");
        assertEquals(2, first.size());
        assertEquals(first, repeated);
        assertTrue(first.contains("Independent banner"));
        assertEquals(
                1L, first.stream().filter(name -> name.startsWith("Checkout ")).count());
    }

    @Test
    void visitorProfileHistoryPaginatesSessionsAndActionsWithIndependentStableCursors() throws Exception {
        Tokens owner = register("visitor-history" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Visitor history\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");

        UUID siteId = UUID.fromString(site);
        String visitor = UUID.randomUUID().toString();
        LocalDate startDate = LocalDate.now(ZoneId.of("UTC")).minusDays(4);
        Instant base = startDate.atTime(1, 0).toInstant(java.time.ZoneOffset.UTC);
        for (int index = 0; index < 53; index++) {
            String session = "history-session-" + index;
            Instant occurred = base.plusSeconds(index * 3600L);
            String path = "/journey/" + index;
            insertRaw(siteId, visitor, session, "page_view", occurred, path);
            insertRaw(siteId, visitor, session, "custom", occurred.plusSeconds(15), path);
        }
        factBuilder.rebuild(siteId, base.minusSeconds(1), base.plusSeconds(53 * 3600L));

        String api = "/api/v1/sites/" + site + "/analytics/visitors/" + visitor;
        String range = "?from=" + startDate + "&to=" + startDate.plusDays(3);
        var initial = given().header("Authorization", "Bearer " + owner.access())
                .get(api + range)
                .then()
                .statusCode(200)
                .body("sessions.size()", is(50))
                .body("actions.size()", is(100))
                .body("hasMoreSessions", is(true))
                .body("hasMoreActions", is(true))
                .extract();
        String sessionsCursor = initial.path("nextSessionsCursor");
        String actionsCursor = initial.path("nextActionsCursor");
        assertNotNull(sessionsCursor);
        assertNotNull(actionsCursor);

        List<String> firstSessionExpected = new java.util.ArrayList<>();
        List<String> firstActionExpected = new java.util.ArrayList<>();
        for (int index = 52; index >= 3; index--) {
            firstSessionExpected.add("history-session-" + index);
            firstActionExpected.add("/journey/" + index);
            firstActionExpected.add("/journey/" + index);
        }
        assertEquals(firstSessionExpected, initial.jsonPath().getList("sessions.sessionId", String.class));
        assertEquals(firstActionExpected, initial.jsonPath().getList("actions.path", String.class));

        var sessionPage = given().header("Authorization", "Bearer " + owner.access())
                .get(api + "/history" + range + "&sessionsCursor=" + sessionsCursor)
                .then()
                .statusCode(200)
                .body("sessions.size()", is(3))
                .body("actions.size()", is(0))
                .body("nextSessionsCursor", nullValue())
                .extract();
        assertEquals(
                List.of("history-session-2", "history-session-1", "history-session-0"),
                sessionPage.jsonPath().getList("sessions.sessionId", String.class));

        var actionPage = given().header("Authorization", "Bearer " + owner.access())
                .get(api + "/history" + range + "&actionsCursor=" + actionsCursor)
                .then()
                .statusCode(200)
                .body("sessions.size()", is(0))
                .body("actions.size()", is(6))
                .body("nextActionsCursor", nullValue())
                .extract();
        assertEquals(
                List.of("/journey/2", "/journey/2", "/journey/1", "/journey/1", "/journey/0", "/journey/0"),
                actionPage.jsonPath().getList("actions.path", String.class));

        given().header("Authorization", "Bearer " + owner.access())
                .get(api + "/history" + range + "&sessionsCursor=invalid")
                .then()
                .statusCode(400);
        String anotherVisitor = UUID.randomUUID().toString();
        insertRaw(siteId, anotherVisitor, "other-history-session", "page_view", base, "/other");
        factBuilder.rebuild(siteId, base.minusSeconds(1), base.plusSeconds(53 * 3600L));
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site + "/analytics/visitors/" + anotherVisitor + "/history" + range
                        + "&sessionsCursor=" + sessionsCursor)
                .then()
                .statusCode(400);
    }

    @Test
    void savedSegmentTargetsOnlyMatchingVisitorsWithinItsLookback() throws Exception {
        Tokens owner = register("experiment-segment" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Segment-targeted tests\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String segmentsPath = "/api/v1/sites/" + site + "/segments";
        String segment = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Pricing visitors\",\"matchMode\":\"all\",\"enabled\":true,"
                        + "\"rules\":[{\"field\":\"page_path\",\"operator\":\"starts_with\",\"value\":\"/pricing\"}]}")
                .post(segmentsPath)
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        String experimentsPath = "/api/v1/sites/" + site + "/experiments";
        String experiment = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Pricing hero\",\"variants\":[\"control\",\"variant\"],"
                        + "\"targeting\":{\"pathPrefixes\":[\"/pricing\"],\"deviceTypes\":[\"desktop\"],"
                        + "\"segmentId\":\"" + segment + "\",\"segmentLookbackDays\":30}}")
                .post(experimentsPath)
                .then()
                .statusCode(200)
                .body("targeting.segmentId", is(segment))
                .body("targeting.segmentLookbackDays", is(30))
                .extract()
                .path("id");

        UUID siteId = UUID.fromString(site);
        String recentVisitor = UUID.randomUUID().toString();
        String oldVisitor = UUID.randomUUID().toString();
        String unmatchedVisitor = UUID.randomUUID().toString();
        Instant recentVisit = Instant.now().minusSeconds(24 * 3600L);
        Instant oldVisit = Instant.now().minusSeconds(45 * 24 * 3600L);
        insertRaw(siteId, recentVisitor, "session-recent", "page_view", recentVisit, "/pricing/plan");
        insertRaw(siteId, oldVisitor, "session-old", "page_view", oldVisit, "/pricing/plan");
        insertRaw(siteId, unmatchedVisitor, "session-unmatched", "page_view", recentVisit, "/company/about");
        factBuilder.rebuild(siteId, oldVisit.minusSeconds(1), Instant.now().plusSeconds(1));

        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"host\":\"experiment-segment.example.test\",\"allowSubdomains\":false,\"enabled\":true}")
                .post("/api/v1/sites/" + site + "/domains")
                .then()
                .statusCode(201);
        String trackingId = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site)
                .then()
                .statusCode(200)
                .extract()
                .path("trackingId");
        String publicPath = "/api/v1/experiments/" + trackingId + "/definitions";
        String origin = "https://experiment-segment.example.test";
        given().header("Origin", origin)
                .get(publicPath + "?visitorId=" + recentVisitor)
                .then()
                .statusCode(200)
                .header("Cache-Control", equalTo("private, no-store"))
                .header("Vary", equalTo("Origin"))
                .body("[0].name", is("Pricing hero"))
                .body("[0].targeting.pathPrefixes", contains("/pricing"))
                .body("[0].targeting.deviceTypes", contains("desktop"))
                .body("[0].targeting.segmentId", nullValue());
        given().header("Origin", origin)
                .get(publicPath + "?visitorId=" + oldVisitor)
                .then()
                .statusCode(200)
                .body("size()", is(0));
        given().header("Origin", origin)
                .get(publicPath + "?visitorId=" + unmatchedVisitor)
                .then()
                .statusCode(200)
                .body("size()", is(0));
        given().header("Origin", origin).get(publicPath).then().statusCode(200).body("size()", is(0));

        String targeting90 = "{\"pathPrefixes\":[\"/pricing\"],\"deviceTypes\":[\"desktop\"]," + "\"segmentId\":\""
                + segment + "\",\"segmentLookbackDays\":90}";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Pricing hero\",\"variants\":[\"control\",\"variant\"]," + "\"targeting\":"
                        + targeting90 + "}")
                .put(experimentsPath + "/" + experiment)
                .then()
                .statusCode(200)
                .body("targeting.segmentLookbackDays", is(90));
        given().header("Origin", origin)
                .get(publicPath + "?visitorId=" + oldVisitor)
                .then()
                .statusCode(200)
                .body("[0].name", is("Pricing hero"));

        String disabledSegment = "{\"name\":\"Pricing visitors\",\"matchMode\":\"all\",\"enabled\":false,"
                + "\"rules\":[{\"field\":\"page_path\",\"operator\":\"starts_with\",\"value\":\"/pricing\"}]}";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(disabledSegment)
                .put(segmentsPath + "/" + segment)
                .then()
                .statusCode(409);
        given().header("Authorization", "Bearer " + owner.access())
                .delete(segmentsPath + "/" + segment)
                .then()
                .statusCode(409);
    }

    @Test
    void experimentReportCountsUniqueExposedAndConvertedSessions() throws Exception {
        Tokens owner = register("experiment-counts" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Experiment counts\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String path = "/api/v1/sites/" + site + "/experiments";
        String experiment = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Checkout CTA\",\"variants\":[\"control\",\"new_copy\"]}")
                .post(path)
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        UUID siteId = UUID.fromString(site);
        Instant occurred = Instant.parse("2026-09-04T12:00:00Z");
        insertRaw(siteId, "visitor-experiment", "session-experiment", "experiment_exposure", occurred, "/checkout");
        insertRaw(
                siteId,
                "visitor-experiment",
                "session-experiment",
                "experiment_exposure",
                occurred.plusSeconds(1),
                "/checkout");
        insertRaw(siteId, "visitor-experiment", "session-experiment", "goal", occurred.plusSeconds(2), "/checkout");
        insertRaw(siteId, "visitor-experiment", "session-experiment", "goal", occurred.plusSeconds(3), "/checkout");
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement(
                        "update raw_event set event_data=case when event_type='experiment_exposure' then '{\"action\":\"Checkout CTA\",\"name\":\"new_copy\"}'::jsonb else '{\"name\":\"purchase\"}'::jsonb end where client_session_id=?")) {
            p.setString(1, "session-experiment");
            p.executeUpdate();
        }
        given().header("Authorization", "Bearer " + owner.access())
                .get(path + "/" + experiment + "/report?from=2026-09-04&to=2026-09-04")
                .then()
                .statusCode(200)
                .body("variants[0].exposures", is(0))
                .body("variants[1].exposures", is(1))
                .body("variants[1].conversions", is(1))
                .body("variants[1].conversionRate", is(1.0f));
    }

    @Test
    void experimentReportIncludesLiftAndSignificance() throws Exception {
        Tokens owner = register("experiment-stats" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Experiment stats\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String path = "/api/v1/sites/" + site + "/experiments";
        String experiment = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Pricing CTA\",\"variants\":[\"control\",\"new_copy\"]}")
                .post(path)
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        UUID siteId = UUID.fromString(site);
        Instant occurred = Instant.parse("2026-09-05T12:00:00Z");
        for (int i = 0; i < 20; i++) {
            String session = "stats-control-" + i;
            insertRaw(
                    siteId,
                    "stats-control-" + i,
                    session,
                    "experiment_exposure",
                    occurred.plusSeconds(i * 10L),
                    "/pricing",
                    "{\"action\":\"Pricing CTA\",\"name\":\"control\"}");
            if (i < 2)
                insertRaw(
                        siteId,
                        "stats-control-" + i,
                        session,
                        "goal",
                        occurred.plusSeconds(i * 10L + 1),
                        "/pricing",
                        "{\"name\":\"purchase\"}");
        }
        for (int i = 0; i < 20; i++) {
            String session = "stats-variant-" + i;
            insertRaw(
                    siteId,
                    "stats-variant-" + i,
                    session,
                    "experiment_exposure",
                    occurred.plusSeconds(500 + i * 10L),
                    "/pricing",
                    "{\"action\":\"Pricing CTA\",\"name\":\"new_copy\"}");
            if (i < 12)
                insertRaw(
                        siteId,
                        "stats-variant-" + i,
                        session,
                        "goal",
                        occurred.plusSeconds(501 + i * 10L),
                        "/pricing",
                        "{\"name\":\"purchase\"}");
        }
        given().header("Authorization", "Bearer " + owner.access())
                .get(path + "/" + experiment + "/report?from=2026-09-05&to=2026-09-05")
                .then()
                .statusCode(200)
                .body("variants[0].conversionRate", is(0.1f))
                .body("variants[0].relativeLift", nullValue())
                .body("variants[0].conversionRateCiLower", greaterThan(0.02f))
                .body("variants[0].conversionRateCiUpper", lessThan(0.31f))
                .body("variants[1].conversionRate", is(0.6f))
                .body("variants[1].relativeLift", is(5.0f))
                .body("variants[1].conversionRateDifference", is(0.5f))
                .body("variants[1].conversionRateDifferenceCiLower", greaterThan(0.20f))
                .body("variants[1].conversionRateDifferenceCiUpper", lessThan(0.70f))
                .body("variants[1].pValue", lessThan(0.01f))
                .body("variants[1].statisticallySignificant", is(true));
    }

    @Test
    void publishesTagManagerContainerAndRestrictsOrigins() {
        Tokens owner = register("tagmanager" + System.nanoTime() + "@example.test");
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Tag manager\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String templatesPath = "/api/v1/sites/" + site + "/tag-manager/templates";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"CTA click\",\"description\":\"Track primary call-to-action clicks\","
                        + "\"tags\":[{\"type\":\"event\",\"trigger\":\"cta_click\","
                        + "\"eventType\":\"cta_click\",\"name\":\"CTA click\"}]}")
                .post(templatesPath)
                .then()
                .statusCode(200)
                .body("name", is("CTA click"))
                .body("tags.size()", is(1));
        String secondSite = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Shared template site\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + secondSite + "/tag-manager/templates")
                .then()
                .statusCode(200)
                .body("size()", is(1))
                .body("[0].name", is("CTA click"));
        String templateId = given().header("Authorization", "Bearer " + owner.access())
                .get(templatesPath)
                .then()
                .statusCode(200)
                .extract()
                .path("[0].id");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Primary CTA click\",\"description\":\"Shared across sites\","
                        + "\"tags\":[{\"type\":\"event\",\"trigger\":\"cta_click\","
                        + "\"eventType\":\"cta_click\",\"name\":\"CTA click\"}]}")
                .put("/api/v1/sites/" + secondSite + "/tag-manager/templates/" + templateId)
                .then()
                .statusCode(200)
                .body("name", is("Primary CTA click"));
        given().header("Authorization", "Bearer " + owner.access())
                .delete(templatesPath + "/" + templateId)
                .then()
                .statusCode(204);
        given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + secondSite + "/tag-manager/templates")
                .then()
                .statusCode(200)
                .body("size()", is(0));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"host\":\"tags.example.test\",\"allowSubdomains\":false,\"enabled\":true}")
                .post("/api/v1/sites/" + site + "/domains")
                .then()
                .statusCode(201);
        String containerPath = "/api/v1/sites/" + site + "/tag-manager/containers";
        String container = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Production\"}")
                .post(containerPath)
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Production tags\",\"enabled\":true}")
                .put(containerPath + "/" + container)
                .then()
                .statusCode(200)
                .body("name", is("Production tags"));
        String draftPath = containerPath + "/" + container + "/versions";
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("[{\"type\":\"html\",\"name\":\"unsafe\"}]")
                .post(draftPath)
                .then()
                .statusCode(400)
                .body("code", is("INVALID_TAG_CONTAINER"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("[{\"type\":\"event\",\"eventType\":\"qualified_signup\",\"triggers\":["
                        + "{\"type\":\"event\",\"event\":\"signup\",\"conditions\":["
                        + "{\"property\":\"plan\",\"operator\":\"matches_regex\",\"value\":\"pro\"}]}]}]")
                .post(draftPath)
                .then()
                .statusCode(400)
                .body("code", is("INVALID_TAG_CONTAINER"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(
                        "[{\"type\":\"event\",\"triggers\":[{\"type\":\"event\",\"event\":\"signup\",\"conditions\":[{\"property\":\"plan\",\"operator\":\"equals\",\"value\":\"pro\"}]}],\"eventType\":\"tag_signup\",\"name\":\"signup_tag\"},"
                                + "{\"type\":\"custom_html\",\"name\":\"Signup pixel\",\"triggers\":[{\"type\":\"predefined\",\"event\":\"page_view\"},{\"type\":\"custom_js\",\"functionName\":\"shouldFireSignupPixel\",\"code\":\"(event) => event.event === 'signup'\"}],\"code\":\"<script>window.signupPixel=true;</script>\"}]")
                .post(draftPath)
                .then()
                .statusCode(200)
                .body("version", is(1))
                .body("status", is("draft"));
        given().header("Authorization", "Bearer " + owner.access())
                .post(draftPath + "/1/publish")
                .then()
                .statusCode(200)
                .body("status", is("published"));
        String trackingId = given().header("Authorization", "Bearer " + owner.access())
                .get("/api/v1/sites/" + site)
                .then()
                .statusCode(200)
                .extract()
                .path("trackingId");
        given().header("Origin", "https://tags.example.test")
                .get("/api/v1/tag-manager/" + trackingId + "/container")
                .then()
                .statusCode(200)
                .body("size()", is(2))
                .body("[0].triggers[0].conditions[0].property", is("plan"))
                .body("[0].triggers[0].conditions[0].operator", is("equals"))
                .body("[1].type", is("custom_html"))
                .body("[1].code", is("<script>window.signupPixel=true;</script>"));
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(
                        "[{\"type\":\"event\",\"trigger\":\"purchase\",\"eventType\":\"tag_purchase\",\"name\":\"purchase_tag\"}]")
                .post(draftPath)
                .then()
                .statusCode(200)
                .body("version", is(2))
                .body("status", is("draft"));
        given().header("Authorization", "Bearer " + owner.access())
                .post(draftPath + "/2/publish")
                .then()
                .statusCode(200)
                .body("status", is("published"));
        given().header("Authorization", "Bearer " + owner.access())
                .post(draftPath + "/1/environments/staging/publish")
                .then()
                .statusCode(200)
                .body("version", is(1))
                .body("status", is("draft"));
        given().header("Authorization", "Bearer " + owner.access())
                .get(containerPath + "/" + container + "/versions")
                .then()
                .statusCode(200)
                .body("size()", is(2))
                .body("[0].version", is(2))
                .body("[0].status", is("published"))
                .body("[1].version", is(1))
                .body("[1].status", is("draft"));
        given().header("Origin", "https://tags.example.test")
                .get("/api/v1/tag-manager/" + trackingId + "/container")
                .then()
                .statusCode(200)
                .body("size()", is(1))
                .body("[0].name", is("purchase_tag"));
        given().header("Origin", "https://tags.example.test")
                .get("/api/v1/tag-manager/" + trackingId + "/container?environment=staging")
                .then()
                .statusCode(200)
                .body("size()", is(2))
                .body("[0].name", is("signup_tag"));
        given().header("Origin", "https://tags.example.test")
                .get("/api/v1/tag-manager/" + trackingId + "/container?environment=invalid")
                .then()
                .statusCode(400)
                .body("code", is("INVALID_TAG_ENVIRONMENT"));
        given().header("Authorization", "Bearer " + owner.access())
                .get(containerPath)
                .then()
                .statusCode(200)
                .body("[0].publishedVersion", is(2))
                .body("[0].environmentVersions.staging", is(1))
                .body("[0].environmentVersions.production", is(2));
        given().header("Origin", "https://evil.example.test")
                .get("/api/v1/tag-manager/" + trackingId + "/container")
                .then()
                .statusCode(403);
        String previewSessionsPath = containerPath + "/" + container + "/preview-sessions";
        var preview = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"tags\":[{\"type\":\"event\",\"trigger\":\"signup\","
                        + "\"eventType\":\"tag_signup\",\"name\":\"Signup tag\"}],"
                        + "\"executeCustomCode\":false}")
                .post(previewSessionsPath)
                .then()
                .statusCode(200)
                .body("executeCustomCode", is(false))
                .extract();
        String previewId = preview.path("sessionId");
        String previewToken = preview.path("token");
        assertNotNull(previewId);
        assertTrue(previewToken.length() >= 40);
        String previewPath = "/api/v1/tag-manager/" + trackingId + "/preview/" + previewId;
        given().header("Origin", "https://evil.example.test")
                .header("Authorization", "Bearer " + previewToken)
                .get(previewPath)
                .then()
                .statusCode(403);
        given().header("Origin", "https://tags.example.test")
                .header("Authorization", "Bearer wrong-token")
                .get(previewPath)
                .then()
                .statusCode(403);
        given().header("Origin", "https://tags.example.test")
                .header("Authorization", "Bearer " + previewToken)
                .get(previewPath)
                .then()
                .statusCode(200)
                .body("executeCustomCode", is(false))
                .body("tags[0].name", is("Signup tag"));
        given().header("Origin", "https://tags.example.test")
                .header("Authorization", "Bearer " + previewToken)
                .contentType("application/json")
                .body("[{\"tagIndex\":0,\"triggerEvent\":\"signup\","
                        + "\"outcome\":\"invalid\",\"pagePath\":\"/signup\"}]")
                .post(previewPath + "/events")
                .then()
                .statusCode(400);
        given().header("Origin", "https://tags.example.test")
                .header("Authorization", "Bearer " + previewToken)
                .contentType("application/json")
                .body("[{\"tagIndex\":0,\"triggerEvent\":\"signup\","
                        + "\"outcome\":\"fired\",\"pagePath\":\"/signup?email=private%40example.test#form\","
                        + "\"properties\":{\"private\":\"must-not-be-stored\"}}]")
                .post(previewPath + "/events")
                .then()
                .statusCode(204);
        given().header("Authorization", "Bearer " + owner.access())
                .get(previewSessionsPath + "/" + previewId + "/events")
                .then()
                .statusCode(200)
                .body("size()", is(1))
                .body("[0].tagName", is("Signup tag"))
                .body("[0].triggerEvent", is("signup"))
                .body("[0].outcome", is("fired"))
                .body("[0].pagePath", is("/signup"))
                .body("[0].properties", nullValue());
        given().header("Authorization", "Bearer " + owner.access())
                .delete(previewSessionsPath + "/" + previewId)
                .then()
                .statusCode(204);
        given().header("Origin", "https://tags.example.test")
                .header("Authorization", "Bearer " + previewToken)
                .get(previewPath)
                .then()
                .statusCode(404);
        given().header("Authorization", "Bearer " + owner.access())
                .delete(containerPath + "/" + container)
                .then()
                .statusCode(204);
    }

    @Test
    void siteAuditLogShowsSuccessfulConfigurationChangesAndEnforcesSiteAccess() {
        String email = "audit" + System.nanoTime() + "@example.test";
        Tokens owner = register(email);
        String workspace = workspace(owner.access()).extract().path("[0].id");
        String site = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Audit history\",\"timezone\":\"UTC\"}")
                .post("/api/v1/workspaces/" + workspace + "/sites")
                .then()
                .statusCode(201)
                .extract()
                .path("id");
        String dashboards = "/api/v1/sites/" + site + "/dashboards";
        String dashboardId = given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body("{\"name\":\"Weekly overview\",\"isDefault\":true,\"widgets\":["
                        + "{\"id\":\"summary\",\"type\":\"summary\",\"title\":\"Overview\"}]}")
                .post(dashboards)
                .then()
                .statusCode(200)
                .extract()
                .path("id");
        given().header("Authorization", "Bearer " + owner.access())
                .post(dashboards + "/" + dashboardId + "/duplicate")
                .then()
                .statusCode(200);

        String today = LocalDate.now(ZoneId.of("UTC")).toString();
        String auditLog = "/api/v1/sites/" + site + "/audit-log";
        var firstPage = given().header("Authorization", "Bearer " + owner.access())
                .get(auditLog + "?from=" + today + "&to=" + today + "&limit=1")
                .then()
                .statusCode(200)
                .body("entries.size()", is(1))
                .body("entries[0].actorEmail", is(email))
                .body("entries[0].action", is("DUPLICATE"))
                .body("entries[0].resourceId", is(dashboardId))
                .extract();
        String cursor = firstPage.path("nextCursor");
        assertNotNull(cursor);
        given().header("Authorization", "Bearer " + owner.access())
                .queryParam("from", today)
                .queryParam("to", today)
                .queryParam("limit", 1)
                .queryParam("cursor", cursor)
                .get(auditLog)
                .then()
                .statusCode(200)
                .body("entries.size()", is(1))
                .body("entries[0].action", is("CREATE"))
                .body("entries[0].resource", is("dashboards"));

        Tokens outsider = register("audit-outsider" + System.nanoTime() + "@example.test");
        given().header("Authorization", "Bearer " + outsider.access())
                .get("/api/v1/sites/" + site + "/audit-log")
                .then()
                .statusCode(404);
    }

    @Test
    void rawRetentionPurgesEventsButKeepsRetainedSessionAndDailyFacts() throws Exception {
        Tokens owner = register("raw-retention" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String site = createSite(owner.access(), workspaceId, "Retention site");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(
                        "{\"name\":\"Retention site\",\"timezone\":\"UTC\",\"rawRetentionDays\":1,\"aggregateRetentionDays\":730}")
                .patch("/api/v1/sites/" + site)
                .then()
                .statusCode(200)
                .body("rawRetentionDays", is(1))
                .body("aggregateRetentionDays", is(730));

        UUID siteId = UUID.fromString(site);
        String visitor = UUID.randomUUID().toString();
        Instant oldVisit = Instant.now().minusSeconds(45L * 24 * 3600);
        Instant recentVisit = Instant.now().minusSeconds(2 * 3600L);
        insertRaw(siteId, visitor, "retained-old-session", "page_view", oldVisit, "/old");
        insertRaw(siteId, visitor, "retained-recent-session", "page_view", recentVisit, "/recent");
        LocalDate oldDay = oldVisit.atZone(ZoneId.of("UTC")).toLocalDate();
        LocalDate today = LocalDate.now(ZoneId.of("UTC"));
        aggregation.rebuild(siteId, oldDay, today);

        RawAnalyticsRetentionService.CleanupSummary summary = rawRetention.clean();
        assertTrue(summary.rawEventsDeleted() >= 1);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "select (select count(*) from raw_event where site_id=?), (select count(*) from analytics_session where site_id=?), (select session_count from analytics_visitor where site_id=? and client_visitor_id=?), (select page_view_count from analytics_page_daily where site_id=? and business_date=? and path='/old')")) {
            statement.setObject(1, siteId);
            statement.setObject(2, siteId);
            statement.setObject(3, siteId);
            statement.setString(4, visitor);
            statement.setObject(5, siteId);
            statement.setObject(6, oldDay);
            try (var result = statement.executeQuery()) {
                assertTrue(result.next());
                assertEquals(1, result.getLong(1));
                assertEquals(2, result.getLong(2));
                assertEquals(2, result.getInt(3));
                assertEquals(1, result.getLong(4));
            }
        }

        factBuilder.rebuild(siteId, recentVisit.minusSeconds(60), Instant.now().plusSeconds(60));
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement("select count(*) from analytics_session where site_id=?")) {
            statement.setObject(1, siteId);
            try (var result = statement.executeQuery()) {
                assertTrue(result.next());
                assertEquals(2, result.getLong(1), "recent reconciliation must not erase older retained facts");
            }
        }
    }

    @Test
    void aggregateRetentionRemovesExpiredSessionsAndDailyRows() throws Exception {
        Tokens owner = register("aggregate-retention" + System.nanoTime() + "@example.test");
        String workspaceId = workspace(owner.access()).extract().path("[0].id");
        String site = createSite(owner.access(), workspaceId, "Aggregate retention site");
        given().header("Authorization", "Bearer " + owner.access())
                .contentType("application/json")
                .body(
                        "{\"name\":\"Aggregate retention site\",\"timezone\":\"UTC\",\"rawRetentionDays\":1,\"aggregateRetentionDays\":10}")
                .patch("/api/v1/sites/" + site)
                .then()
                .statusCode(200);

        UUID siteId = UUID.fromString(site);
        String visitor = UUID.randomUUID().toString();
        Instant oldVisit = Instant.now().minusSeconds(45L * 24 * 3600);
        Instant recentVisit = Instant.now().minusSeconds(2 * 3600L);
        insertRaw(siteId, visitor, "expired-session", "page_view", oldVisit, "/expired");
        insertRaw(siteId, visitor, "current-session", "page_view", recentVisit, "/current");
        LocalDate oldDay = oldVisit.atZone(ZoneId.of("UTC")).toLocalDate();
        LocalDate today = LocalDate.now(ZoneId.of("UTC"));
        aggregation.rebuild(siteId, oldDay, today);

        RawAnalyticsRetentionService.CleanupSummary summary = rawRetention.clean();
        assertTrue(summary.sessionsDeleted() >= 1);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "select (select count(*) from analytics_session where site_id=?), (select count(*) from analytics_page_daily where site_id=? and business_date=? and path='/expired'), (select session_count from analytics_visitor where site_id=? and client_visitor_id=?)")) {
            statement.setObject(1, siteId);
            statement.setObject(2, siteId);
            statement.setObject(3, oldDay);
            statement.setObject(4, siteId);
            statement.setString(5, visitor);
            try (var result = statement.executeQuery()) {
                assertTrue(result.next());
                assertEquals(1, result.getLong(1));
                assertEquals(0, result.getLong(2));
                assertEquals(1, result.getInt(3));
            }
        }
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
        insertAnalyticsRaw(
                siteId, visitor, session, type, occurred, path, referrer, source, medium, campaign, null, null);
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
            String campaign,
            String term,
            String content)
            throws Exception {
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement(
                        "insert into raw_event(ingest_id,site_id,client_event_id,client_visitor_id,client_session_id,received_at,occurred_at,event_type,page_host,page_path,referrer_host,utm_source,utm_medium,utm_campaign,utm_term,utm_content,event_data,ingest_version) values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?::jsonb,1)")) {
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
            p.setString(15, term);
            p.setString(16, content);
            p.setString(17, "custom".equals(type) ? "{\"interaction\":true}" : "{}");
            p.executeUpdate();
        }
    }

    private void insertRaw(UUID siteId, String visitor, String session, String type, Instant occurred, String path)
            throws Exception {
        insertRaw(siteId, visitor, session, type, occurred, path, "{}");
    }

    private void insertAttributionPage(
            UUID siteId,
            String visitor,
            String session,
            Instant occurred,
            String path,
            String referrer,
            String source,
            String medium,
            String campaign)
            throws Exception {
        insertRaw(siteId, visitor, session, "page_view", occurred, path);
        try (var connection = dataSource.getConnection();
                var statement = connection.prepareStatement(
                        "update raw_event set page_host='www.example.test',referrer_host=?,utm_source=?,utm_medium=?,utm_campaign=? where site_id=? and client_session_id=?")) {
            statement.setString(1, referrer);
            statement.setString(2, source);
            statement.setString(3, medium);
            statement.setString(4, campaign);
            statement.setObject(5, siteId);
            statement.setString(6, session);
            statement.executeUpdate();
        }
    }

    private void insertRaw(
            UUID siteId, String visitor, String session, String type, Instant occurred, String path, String eventData)
            throws Exception {
        try (var c = dataSource.getConnection();
                var p = c.prepareStatement(
                        "insert into raw_event(ingest_id,site_id,client_event_id,client_visitor_id,client_session_id,received_at,occurred_at,event_type,page_path,event_data,ingest_version) values(?,?,?,?,?,?,?,?,?,?::jsonb,1)")) {
            p.setObject(1, UUID.randomUUID());
            p.setObject(2, siteId);
            p.setObject(3, UUID.randomUUID());
            p.setString(4, visitor);
            p.setString(5, session);
            p.setTimestamp(6, java.sql.Timestamp.from(occurred.plusSeconds(1)));
            p.setTimestamp(7, java.sql.Timestamp.from(occurred));
            p.setString(8, type);
            p.setString(9, path);
            p.setString(10, eventData);
            p.executeUpdate();
        }
    }

    private static double attributionCredit(List<?> rows, String channel) {
        return rows.stream()
                .map(row -> (java.util.Map<?, ?>) row)
                .filter(row -> channel.equals(row.get("channel")))
                .map(row -> ((Number) row.get("attributedConversions")).doubleValue())
                .mapToDouble(Double::doubleValue)
                .sum();
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
