package io.seeray.lens.android

import java.io.File
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertThrows
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
        val visitorId = store.get("srl_test:visitor_id")
        assertTrue(visitorId != null)

        client.optOut()
        assertEquals(AnalyticsConsent.DENIED, client.consentState())
        assertEquals(0, client.pendingEventCount())
        assertEquals(null, store.get("srl_test:visitor_id"))
        assertEquals(null, store.get("srl_test:session_id"))
        assertEquals(null, store.get("srl_test:session_last_activity"))
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
        val first = store.get("srl_test:session_id")
        val visitor = store.get("srl_test:visitor_id")
        clock.advance(Duration.ofMinutes(31))
        client.trackPageView("https://www.example.test/second")

        assertNotEquals(first, store.get("srl_test:session_id"))
        assertEquals(visitor, store.get("srl_test:visitor_id"))
    }

    @Test
    fun identitiesAndConsentAreIsolatedPerTrackingId() {
        val store = MemoryAnalyticsStore()
        val first = client(
            SeeRayAnalyticsOptions("srl_first", "https://lens.example.test", requireConsent = true),
            store,
            RecordingTransport(),
        )
        val second = client(
            SeeRayAnalyticsOptions("srl_second", "https://lens.example.test", requireConsent = true),
            store,
            RecordingTransport(),
        )

        first.setConsent(true)
        first.trackPageView("https://first.example.test/")
        second.setConsent(true)
        second.trackPageView("https://second.example.test/")
        val firstVisitor = store.get("srl_first:visitor_id")
        val secondVisitor = store.get("srl_second:visitor_id")

        assertNotEquals(firstVisitor, secondVisitor)
        first.optOut()
        assertEquals(null, store.get("srl_first:visitor_id"))
        assertEquals(secondVisitor, store.get("srl_second:visitor_id"))
        assertEquals(AnalyticsConsent.GRANTED, second.consentState())
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

    @Test
    fun nativeCrashRequiresSeparateConsentPersistsRedactedTopFrameAndResumesNextLaunch() {
        val store = MemoryAnalyticsStore()
        val options = SeeRayAnalyticsOptions(
            siteId = "srl_test",
            apiOrigin = "https://lens.example.test",
            requireConsent = true,
            captureNativeCrashes = true,
            appRelease = "android-4.2.1+88",
            crashContextUrl = "https://www.example.test/",
        )
        val first = client(options, store, RecordingTransport())
        first.setConsent(true)
        first.trackScreen("checkout", "https://www.example.test/orders/12345678?token=page-secret")

        first.captureNativeCrash(
            IllegalStateException("token=private-token failed for alice@example.test at https://secret.example.test/id/12345678"),
        )
        assertTrue(store.pendingNativeCrashes("srl_test").isEmpty())

        first.setNativeCrashConsent(true)
        first.captureNativeCrash(
            IllegalStateException("token=private-token failed for alice@example.test at https://secret.example.test/id/12345678"),
        )
        val saved = store.pendingNativeCrashes("srl_test").single()
        assertTrue(saved.url.startsWith("https://www.example.test/"))
        assertFalse(saved.url.contains("12345678"))
        assertFalse(saved.message.contains("private-token"))
        assertFalse(saved.message.contains("alice@example.test"))
        assertFalse(saved.message.contains("secret.example.test"))

        first.close()
        val transport = RecordingTransport()
        val nextLaunch = client(options, store, transport)
        assertEquals(1, nextLaunch.pendingEventCount())
        assertTrue(nextLaunch.flush().get())

        val body = transport.bodies.single()
        assertTrue(body.contains("\"type\":\"client_error\""))
        assertTrue(body.contains("\"action\":\"native_android\""))
        assertTrue(body.contains("\"platform\":\"android\""))
        assertTrue(body.contains("\"releaseId\":\"android-4.2.1+88\""))
        assertFalse(body.contains("\"visitorId\""))
        assertFalse(body.contains("\"sessionId\""))
        assertFalse(body.contains("private-token"))
        assertFalse(body.contains("alice@example.test"))
        assertTrue(store.pendingNativeCrashes("srl_test").isEmpty())
    }

    @Test
    fun nativeCrashCollectionRequiresReleaseAndHttpsSiteContext() {
        assertThrows(IllegalArgumentException::class.java) {
            SeeRayAnalyticsOptions(
                siteId = "srl_test",
                apiOrigin = "https://lens.example.test",
                captureNativeCrashes = true,
                appRelease = "android-1",
                crashContextUrl = "http://www.example.test/",
            ).let { SeeRayAnalytics(it, MemoryAnalyticsStore(), RecordingTransport(), startScheduler = false) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            SeeRayAnalyticsOptions(
                siteId = "srl_test",
                apiOrigin = "https://lens.example.test",
                captureNativeCrashes = true,
                crashContextUrl = "https://www.example.test/",
            ).let { SeeRayAnalytics(it, MemoryAnalyticsStore(), RecordingTransport(), startScheduler = false) }
        }
    }

    @Test
    fun noBackupCrashOutboxPersistsBySiteAndRemovesAcceptedReports() {
        val root = File.createTempFile("srl-crash-test-", "").apply {
            delete()
            mkdirs()
        }
        try {
            val outbox = NoBackupCrashOutbox(root)
            val report = PendingNativeCrash(
                eventId = UUID.randomUUID().toString(),
                occurredAt = "2026-09-19T01:02:03Z",
                url = "https://www.example.test/checkout",
                errorName = "IllegalStateException",
                message = "redacted diagnostic",
                sourcePath = "CheckoutActivity.kt",
                line = 48,
                functionName = "com.example.CheckoutActivity.onCreate",
                releaseId = "android-1.2.3+4",
            )
            outbox.save("srl_first", report)

            assertEquals(listOf(report), outbox.pending("srl_first"))
            assertTrue(outbox.pending("srl_second").isEmpty())
            outbox.remove("srl_first", report.eventId)
            assertTrue(outbox.pending("srl_first").isEmpty())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun nativeCrashHandlerDelegatesToThePreviouslyInstalledHandler() {
        val original = Thread.getDefaultUncaughtExceptionHandler()
        var delegated = false
        Thread.setDefaultUncaughtExceptionHandler { _, _ -> delegated = true }
        val store = MemoryAnalyticsStore()
        val client = client(
            SeeRayAnalyticsOptions(
                siteId = "srl_test",
                apiOrigin = "https://lens.example.test",
                captureNativeCrashes = true,
                appRelease = "android-1",
                crashContextUrl = "https://www.example.test/",
            ),
            store,
            RecordingTransport(),
        )
        try {
            client.setNativeCrashConsent(true)
            Thread.getDefaultUncaughtExceptionHandler()!!
                .uncaughtException(Thread.currentThread(), IllegalStateException("safe"))

            assertTrue(delegated)
            assertEquals(1, store.pendingNativeCrashes("srl_test").size)
        } finally {
            client.close()
            Thread.setDefaultUncaughtExceptionHandler(original)
        }
    }

    @Test
    fun nativeCrashHandlerDoesNotReplaceMissingHostHandler() {
        val original = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler(null)
        try {
            val client = client(
                SeeRayAnalyticsOptions(
                    siteId = "srl_test",
                    apiOrigin = "https://lens.example.test",
                    captureNativeCrashes = true,
                    appRelease = "android-1",
                    crashContextUrl = "https://www.example.test/",
                ),
                MemoryAnalyticsStore(),
                RecordingTransport(),
            )

            assertEquals(null, Thread.getDefaultUncaughtExceptionHandler())
            client.close()
        } finally {
            Thread.setDefaultUncaughtExceptionHandler(original)
        }
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
    private val crashes = mutableMapOf<String, MutableList<PendingNativeCrash>>()
    override fun get(key: String): String? = values[key]
    override fun put(key: String, value: String) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
    override fun saveNativeCrash(siteId: String, report: PendingNativeCrash) {
        val siteCrashes = crashes.getOrPut(siteId, ::mutableListOf)
        if (siteCrashes.size < 10) siteCrashes += report
    }
    override fun pendingNativeCrashes(siteId: String): List<PendingNativeCrash> = crashes[siteId].orEmpty().toList()
    override fun removeNativeCrash(siteId: String, eventId: String) {
        crashes[siteId]?.removeAll { it.eventId == eventId }
    }
    override fun clearNativeCrashes(siteId: String) { crashes.remove(siteId) }
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
