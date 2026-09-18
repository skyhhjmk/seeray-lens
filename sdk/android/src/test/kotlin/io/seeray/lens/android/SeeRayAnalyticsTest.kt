package io.seeray.lens.android

import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class SeeRayAnalyticsTest {
    private val clients = mutableListOf<SeeRayAnalytics>()

    @AfterEach
    fun closeClients() = clients.forEach(SeeRayAnalytics::close)

    @Test
    fun requiredConsentBlocksCollectionUntilAcceptedAndRejectClearsState() {
        val store = MemoryAnalyticsStore()
        val transport = RecordingTransport()
        val client = client(
            SeeRayAnalyticsOptions("srl_test", "https://lens.example.test", requireConsent = true),
            store,
            transport,
        )

        assertEquals(AnalyticsConsent.UNKNOWN, client.consentState())
        client.trackPageView("https://www.example.test/home")
        assertEquals(0, client.pendingEventCount())

        client.setConsent(true)
        client.trackPageView("https://www.example.test/home", title = "Home")
        assertEquals(1, client.pendingEventCount())
        val visitorId = store.get("visitor_id")
        assertTrue(visitorId != null)

        client.optOut()
        assertEquals(AnalyticsConsent.DENIED, client.consentState())
        assertEquals(0, client.pendingEventCount())
        assertEquals(null, store.get("visitor_id"))
        assertEquals(null, store.get("session_id"))
        assertEquals(null, store.get("session_last_activity"))
        assertTrue(transport.bodies.isEmpty())
    }

    @Test
    fun postsSchemaCompatibleEventsAndRetainsFailedBatchForRetry() {
        val transport = RecordingTransport(results = ArrayDeque(listOf(false, true)))
        val client = client(
            SeeRayAnalyticsOptions("srl_test", "https://lens.example.test", batchSize = 10),
            MemoryAnalyticsStore(),
            transport,
        )

        client.trackEvent(
            eventType = "signup",
            url = "https://www.example.test/signup?email=private@example.test",
            category = "account",
            action = "completed",
            name = "mobile \"signup\"",
            properties = mapOf("plan" to "starter", "step" to 2, "enabled" to true, "ignored" to Any()),
        )
        assertFalse(client.flush().get())
        assertEquals(1, client.pendingEventCount())
        assertTrue(client.flush().get())
        assertEquals(0, client.pendingEventCount())

        val body = transport.bodies.last()
        assertTrue(body.startsWith("{\"schemaVersion\":1,"))
        assertTrue(body.contains("\"siteId\":\"srl_test\""))
        assertTrue(body.contains("\"type\":\"signup\""))
        assertTrue(body.contains("\"visitorId\":"))
        assertTrue(body.contains("\"sessionId\":"))
        assertTrue(body.contains("\"operatingSystem\":\"Android\""))
        assertTrue(body.contains("\"plan\":\"starter\""))
        assertTrue(body.contains("\"name\":\"mobile \\\"signup\\\"\""))
        assertTrue(body.contains("https://www.example.test/signup"))
        assertFalse(body.contains("email="))
        assertFalse(body.contains("private@example.test"))
        assertFalse(body.contains("ignored"))
        assertTrue(transport.endpoints.all { it == "https://lens.example.test/api/v1/collect" })
    }

    @Test
    fun visitorIdentityPersistsWhileSessionsRotateAfterInactivity() {
        val store = MemoryAnalyticsStore()
        val clock = MutableClock(Instant.parse("2026-09-19T00:00:00Z"))
        val client = client(
            SeeRayAnalyticsOptions("srl_test", "https://lens.example.test"),
            store,
            RecordingTransport(),
            clock,
        )

        client.trackPageView("https://www.example.test/first")
        val first = store.get("session_id")
        val visitor = store.get("visitor_id")
        clock.advance(Duration.ofMinutes(31))
        client.trackPageView("https://www.example.test/second")

        assertNotEquals(first, store.get("session_id"))
        assertEquals(visitor, store.get("visitor_id"))
    }

    @Test
    fun unsafeUrlsAndUnconfiguredEventTypesAreIgnored() {
        val client = client(
            SeeRayAnalyticsOptions("srl_test", "https://lens.example.test"),
            MemoryAnalyticsStore(),
            RecordingTransport(),
        )

        client.trackPageView("file:///private.txt")
        client.trackEvent("space not an event type", "https://www.example.test/")

        assertEquals(0, client.pendingEventCount())
    }

    private fun client(
        options: SeeRayAnalyticsOptions,
        store: AnalyticsStore,
        transport: AnalyticsTransport,
        clock: Clock = Clock.systemUTC(),
    ) = SeeRayAnalytics(options, store, transport, clock, startScheduler = false).also(clients::add)
}

private class MemoryAnalyticsStore : AnalyticsStore {
    private val values = mutableMapOf<String, String>()
    override fun get(key: String): String? = values[key]
    override fun put(key: String, value: String) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

private class RecordingTransport(
    private val results: ArrayDeque<Boolean> = ArrayDeque(listOf(true)),
) : AnalyticsTransport {
    val endpoints = mutableListOf<String>()
    val bodies = mutableListOf<String>()
    override fun post(endpoint: String, body: String): Boolean {
        endpoints += endpoint
        bodies += body
        return results.removeFirstOrNull() ?: true
    }
}

private class MutableClock(private var current: Instant) : Clock() {
    override fun getZone(): ZoneId = ZoneOffset.UTC
    override fun withZone(zone: ZoneId): Clock = this
    override fun instant(): Instant = current
    fun advance(duration: Duration) { current = current.plus(duration) }
}
