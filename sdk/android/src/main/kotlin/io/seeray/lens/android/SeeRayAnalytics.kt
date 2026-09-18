package io.seeray.lens.android

import android.content.Context
import android.content.SharedPreferences
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.ArrayDeque
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.FutureTask
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

data class SeeRayAnalyticsOptions(
    val siteId: String,
    val apiOrigin: String,
    val requireConsent: Boolean = false,
    val batchSize: Int = 10,
    val flushInterval: Duration = Duration.ofSeconds(10),
    val captureNativeCrashes: Boolean = false,
    val appRelease: String? = null,
    val crashContextUrl: String? = null,
)

enum class AnalyticsConsent { UNKNOWN, GRANTED, DENIED }

/**
 * Privacy-conscious Android event client for SeeRay Lens.
 *
 * Call [trackPageView] when an app screen becomes visible and [trackEvent] for meaningful
 * interactions. No screen, lifecycle, advertising ID, device model, or user identity is collected
 * automatically.
 */
class SeeRayAnalytics internal constructor(
    private val options: SeeRayAnalyticsOptions,
    private val store: AnalyticsStore,
    private val transport: AnalyticsTransport,
    private val clock: Clock = Clock.systemUTC(),
    startScheduler: Boolean = true,
) : Closeable {
    constructor(context: Context, options: SeeRayAnalyticsOptions) : this(
        options = options.validated(),
        store = AndroidAnalyticsStore(context.applicationContext),
        transport = UrlConnectionAnalyticsTransport(),
    )

    private val lock = Any()
    private val queue = ArrayDeque<AnalyticsEvent>()
    private val sending = AtomicBoolean(false)
    private val closing = AtomicBoolean(false)
    private val batchSize = options.batchSize.coerceIn(1, MAX_BATCH_SIZE)
    private val endpoint = endpoint(options.apiOrigin)
    private val scheduler: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "seeray-analytics").apply { isDaemon = true }
    }
    private var visitorId: String? = null
    private var sessionId: String? = null
    private var sessionLastActivity: Long? = null
    private var userId: String? = null
    private var droppedEventCount = 0L
    private val queuedNativeCrashIds = mutableSetOf<String>()
    private var previousExceptionHandler: Thread.UncaughtExceptionHandler? = null
    private var installedExceptionHandler: Thread.UncaughtExceptionHandler? = null
    private var lastPageUrl: String? = null

    init {
        options.validated()
        if (startScheduler) {
            val interval = options.flushInterval.toMillis().coerceIn(MIN_FLUSH_MS, MAX_FLUSH_MS)
            scheduler.scheduleWithFixedDelay({ flush() }, interval, interval, TimeUnit.MILLISECONDS)
        }
        if (options.captureNativeCrashes) {
            installNativeCrashHandler()
            synchronized(lock) { restorePendingNativeCrashes() }
        } else {
            store.clearNativeCrashes(options.siteId)
            removeStored(KEY_LAST_PAGE_URL)
        }
    }

    fun consentState(): AnalyticsConsent = synchronized(lock) {
        when (readStored(KEY_CONSENT)) {
            CONSENT_GRANTED -> AnalyticsConsent.GRANTED
            CONSENT_DENIED -> AnalyticsConsent.DENIED
            else -> if (options.requireConsent) AnalyticsConsent.UNKNOWN else AnalyticsConsent.GRANTED
        }
    }

    /** Records an explicit visitor choice. Denial immediately removes local IDs and queued events. */
    fun setConsent(granted: Boolean) {
        synchronized(lock) {
            if (granted) {
                writeStored(KEY_CONSENT, CONSENT_GRANTED)
                ensureIdentity(clock.millis())
            } else {
                writeStored(KEY_CONSENT, CONSENT_DENIED)
                writeStored(KEY_NATIVE_CRASH_CONSENT, CONSENT_DENIED)
                clearIdentity()
                lastPageUrl = null
                removeStored(KEY_LAST_PAGE_URL)
                queue.clear()
                queuedNativeCrashIds.clear()
                userId = null
                store.clearNativeCrashes(options.siteId)
            }
        }
        if (granted) synchronized(lock) { restorePendingNativeCrashes() }
    }

    fun optOut() = setConsent(granted = false)

    /** Native crash diagnostics always require a separate, explicit application-level choice. */
    fun setNativeCrashConsent(granted: Boolean) {
        synchronized(lock) {
            val allowed = granted && consentState() == AnalyticsConsent.GRANTED && options.captureNativeCrashes
            writeStored(KEY_NATIVE_CRASH_CONSENT, if (allowed) CONSENT_GRANTED else CONSENT_DENIED)
            if (allowed) {
                restorePendingNativeCrashes()
            } else {
                queue.removeAll { it.pendingCrashId != null }
                queuedNativeCrashIds.clear()
                store.clearNativeCrashes(options.siteId)
            }
        }
        if (granted && pendingEventCount() >= batchSize) flush()
    }

    /**
     * Sets an opaque application-owned ID only while consent is granted. The server hashes it
     * before persistence. Clear it on logout/account switch; never pass an email or other PII.
     */
    fun setUserId(value: String?) {
        synchronized(lock) {
            userId = if (consentState() == AnalyticsConsent.GRANTED) cleanUserId(value) else null
        }
    }

    fun trackPageView(url: String, title: String? = null, referrer: String? = null) = record(
        type = "page_view",
        url = url,
        title = title,
        referrer = referrer,
    )

    fun trackScreen(screenName: String, url: String, title: String? = screenName) = record(
        type = "page_view",
        url = url,
        title = title,
        properties = mapOf("screen" to screenName),
    )

    /**
     * Records a configured goal event. For named goals, prefer [trackEvent] using the event type
     * and name configured in the SeeRay goal editor.
     */
    fun trackGoal(name: String, url: String, properties: Map<String, Any?> = emptyMap()) = record(
        type = "goal",
        url = url,
        name = name,
        properties = properties,
    )

    fun trackEvent(
        eventType: String,
        url: String,
        category: String? = null,
        action: String? = null,
        name: String? = null,
        properties: Map<String, Any?> = emptyMap(),
    ) {
        val cleanType = cleanEventType(eventType) ?: return
        record(
            type = cleanType,
            url = url,
            category = category,
            action = action,
            name = name,
            properties = properties,
        )
    }

    fun pendingEventCount(): Int = synchronized(lock) { queue.size }

    fun droppedEventCount(): Long = synchronized(lock) { droppedEventCount }

    /** Sends one bounded batch off the calling thread. Failed batches remain queued for retry. */
    fun flush(): Future<Boolean> = try {
        scheduler.submit<Boolean> { sendOneBatch() }
    } catch (_: java.util.concurrent.RejectedExecutionException) {
        FutureTask<Boolean> { false }.apply { run() }
    }

    override fun close() {
        if (!closing.compareAndSet(false, true)) return
        installedExceptionHandler?.let { installed ->
            if (Thread.getDefaultUncaughtExceptionHandler() === installed) {
                Thread.setDefaultUncaughtExceptionHandler(previousExceptionHandler)
            }
        }
        try {
            // Drain one final batch on the worker. Never block an Activity/main-thread shutdown.
            scheduler.execute {
                try {
                    sendOneBatch()
                } finally {
                    scheduler.shutdown()
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            scheduler.shutdownNow()
        }
    }

    private fun record(
        type: String,
        url: String,
        title: String? = null,
        referrer: String? = null,
        category: String? = null,
        action: String? = null,
        name: String? = null,
        properties: Map<String, Any?> = emptyMap(),
    ) {
        val pageUrl = validatedPageUrl(url) ?: return
        val eventType = cleanEventType(type) ?: return
        synchronized(lock) {
            if (closing.get()) return
            if (consentState() != AnalyticsConsent.GRANTED) return
            if (queue.size >= MAX_PENDING_EVENTS) {
                droppedEventCount++
                return
            }
            val now = clock.instant()
            if (options.captureNativeCrashes) {
                lastPageUrl = safeCrashPageUrl(pageUrl)
                lastPageUrl?.let { writeStored(KEY_LAST_PAGE_URL, it) }
            }
            val ids = ensureIdentity(now.toEpochMilli())
            queue.addLast(
                AnalyticsEvent(
                    eventId = UUID.randomUUID().toString(),
                    type = eventType,
                    occurredAt = now.toString(),
                    url = pageUrl,
                    title = boundedText(title, MAX_TITLE),
                    referrer = validatedPageUrl(referrer),
                    visitorId = ids.first,
                    sessionId = ids.second,
                    userId = userId,
                    category = boundedText(category, MAX_CATEGORY),
                    action = boundedText(action, MAX_CATEGORY),
                    name = boundedText(name, MAX_NAME),
                    properties = cleanProperties(properties),
                    language = Locale.getDefault().toLanguageTag().take(MAX_LANGUAGE),
                    androidVersion = android.os.Build.VERSION.RELEASE?.take(MAX_VERSION),
                    pendingCrashId = null,
                ),
            )
        }
        if (pendingEventCount() >= batchSize) flush()
    }

    private fun sendOneBatch(): Boolean {
        if (!sending.compareAndSet(false, true)) return false
        val batch = synchronized(lock) {
            if (consentState() != AnalyticsConsent.GRANTED || queue.isEmpty()) {
                emptyList()
            } else {
                buildList { repeat(minOf(batchSize, queue.size)) { add(queue.removeFirst()) } }
            }
        }
        if (batch.isEmpty()) {
            sending.set(false)
            return true
        }
        val success = try {
            transport.post(endpoint, TrackingRequest(options.siteId, clock.instant().toString(), batch).toJson())
        } catch (_: Exception) {
            false
        }
        synchronized(lock) {
            if (consentState() == AnalyticsConsent.GRANTED) {
                if (success) {
                    writeStored(KEY_SESSION_LAST_ACTIVITY, clock.millis().toString())
                    sessionLastActivity = clock.millis()
                    batch.mapNotNull { it.pendingCrashId }.forEach { crashId ->
                        store.removeNativeCrash(options.siteId, crashId)
                        queuedNativeCrashIds.remove(crashId)
                    }
                } else {
                    for (event in batch.asReversed()) {
                        if (queue.size < MAX_PENDING_EVENTS) queue.addFirst(event) else droppedEventCount++
                    }
                }
            }
        }
        sending.set(false)
        return success
    }

    /** Persist a redacted, anonymous top frame before the platform terminates the process. */
    internal fun captureNativeCrash(throwable: Throwable) {
        if (!options.captureNativeCrashes || closing.get()) return
        synchronized(lock) {
            if (consentState() != AnalyticsConsent.GRANTED
                || readStored(KEY_NATIVE_CRASH_CONSENT) != CONSENT_GRANTED) return
            val pageUrl = safeCrashPageUrl(lastPageUrl ?: readStored(KEY_LAST_PAGE_URL) ?: options.crashContextUrl)
                ?: return
            val frame = throwable.stackTrace.firstOrNull { element ->
                !element.className.startsWith("io.seeray.lens.android.")
                    && !element.className.startsWith("java.lang.Thread")
            }
            val errorName = cleanErrorName(throwable.javaClass.simpleName)
            val framePath = frame?.fileName?.substringAfterLast('/')?.substringAfterLast('\\')
                ?.filterNot(Char::isISOControl)?.take(160)?.takeIf(String::isNotBlank)
                ?: frame?.className?.filter { it.isLetterOrDigit() || it in "._-" || it == '$' }?.take(160)
                ?: "Android"
            val functionName = frame?.let { "${it.className}.${it.methodName}" }
                ?.filterNot(Char::isISOControl)?.take(240)
            val report = PendingNativeCrash(
                eventId = UUID.randomUUID().toString(),
                occurredAt = clock.instant().toString(),
                url = pageUrl,
                errorName = errorName,
                message = sanitizeCrashMessage(throwable.message),
                sourcePath = safeCrashPath(framePath),
                line = frame?.lineNumber?.takeIf { it > 0 },
                functionName = functionName,
                releaseId = options.appRelease,
            )
            runCatching { store.saveNativeCrash(options.siteId, report) }
        }
    }

    private fun installNativeCrashHandler() {
        previousExceptionHandler = Thread.getDefaultUncaughtExceptionHandler()
        val next = previousExceptionHandler ?: return
        val handler = Thread.UncaughtExceptionHandler { thread, error ->
            runCatching { captureNativeCrash(error) }
            next.uncaughtException(thread, error)
        }
        installedExceptionHandler = handler
        Thread.setDefaultUncaughtExceptionHandler(handler)
    }

    private fun restorePendingNativeCrashes() {
        if (!options.captureNativeCrashes
            || consentState() != AnalyticsConsent.GRANTED
            || readStored(KEY_NATIVE_CRASH_CONSENT) != CONSENT_GRANTED) return
        store.pendingNativeCrashes(options.siteId).take(MAX_PENDING_CRASH_REPORTS).forEach { report ->
            if (!queuedNativeCrashIds.add(report.eventId)) return@forEach
            if (queue.size >= MAX_PENDING_EVENTS) {
                queuedNativeCrashIds.remove(report.eventId)
                return@forEach
            }
            queue.addLast(report.toAnalyticsEvent())
        }
    }

    private fun ensureIdentity(nowMillis: Long): Pair<String, String> {
        if (visitorId == null) visitorId = readStored(KEY_VISITOR_ID) ?: UUID.randomUUID().toString().also {
            writeStored(KEY_VISITOR_ID, it)
        }
        val persistedLastActivity = sessionLastActivity ?: readStored(KEY_SESSION_LAST_ACTIVITY)?.toLongOrNull()
        val currentSession = sessionId ?: readStored(KEY_SESSION_ID)
        if (currentSession == null || persistedLastActivity == null || nowMillis - persistedLastActivity >= SESSION_TIMEOUT_MS) {
            sessionId = UUID.randomUUID().toString()
            writeStored(KEY_SESSION_ID, sessionId!!)
        } else {
            sessionId = currentSession
        }
        sessionLastActivity = nowMillis
        writeStored(KEY_SESSION_LAST_ACTIVITY, nowMillis.toString())
        return visitorId!! to sessionId!!
    }

    private fun clearIdentity() {
        visitorId = null
        sessionId = null
        sessionLastActivity = null
        removeStored(KEY_VISITOR_ID)
        removeStored(KEY_SESSION_ID)
        removeStored(KEY_SESSION_LAST_ACTIVITY)
    }

    private fun readStored(key: String): String? = store.get("${options.siteId}:$key")

    private fun writeStored(key: String, value: String) = store.put("${options.siteId}:$key", value)

    private fun removeStored(key: String) = store.remove("${options.siteId}:$key")

    private data class AnalyticsEvent(
        val eventId: String,
        val type: String,
        val occurredAt: String,
        val url: String,
        val title: String?,
        val referrer: String?,
        val visitorId: String?,
        val sessionId: String?,
        val userId: String?,
        val category: String?,
        val action: String?,
        val name: String?,
        val properties: Map<String, Any>,
        val language: String,
        val androidVersion: String?,
        val pendingCrashId: String?,
    ) {
        fun toJson(): String = jsonObject(
            linkedMapOf(
                "eventId" to eventId,
                "type" to type,
                "occurredAt" to occurredAt,
                "url" to url,
                "title" to title,
                "referrer" to referrer,
                "visitorId" to visitorId,
                "sessionId" to sessionId,
                "userId" to userId,
                "category" to category,
                "action" to action,
                "name" to name,
                "properties" to properties,
                "context" to linkedMapOf(
                    "browser" to "Other",
                    "operatingSystem" to "Android",
                    "operatingSystemVersion" to androidVersion,
                    "deviceType" to "mobile",
                    "language" to language,
                ),
            ),
        )
    }

    private data class TrackingRequest(val siteId: String, val sentAt: String, val events: List<AnalyticsEvent>) {
        fun toJson(): String = jsonObject(
            linkedMapOf(
                "schemaVersion" to 1,
                "siteId" to siteId,
                "sentAt" to sentAt,
                "events" to events.map { JsonFragment(it.toJson()) },
            ),
        )
    }

    private fun PendingNativeCrash.toAnalyticsEvent(): AnalyticsEvent {
        val data = linkedMapOf<String, Any>(
            "errorName" to errorName,
            "message" to message,
            "sourcePath" to sourcePath,
            "platform" to "android",
            "releaseId" to (releaseId ?: ""),
            "functionName" to (functionName ?: ""),
        )
        if (line != null) data["line"] = line
        data.entries.removeIf { it.value == "" }
        return AnalyticsEvent(
            eventId = eventId,
            type = "client_error",
            occurredAt = occurredAt,
            url = url,
            title = null,
            referrer = null,
            visitorId = null,
            sessionId = null,
            userId = null,
            category = "error",
            action = "native_android",
            name = errorName,
            properties = data,
            language = Locale.getDefault().toLanguageTag().take(MAX_LANGUAGE),
            androidVersion = android.os.Build.VERSION.RELEASE?.take(MAX_VERSION),
            pendingCrashId = eventId,
        )
    }

    private data class JsonFragment(val value: String)

    companion object {
        private const val KEY_CONSENT = "consent"
        private const val KEY_NATIVE_CRASH_CONSENT = "native_crash_consent"
        private const val KEY_VISITOR_ID = "visitor_id"
        private const val KEY_SESSION_ID = "session_id"
        private const val KEY_SESSION_LAST_ACTIVITY = "session_last_activity"
        private const val KEY_LAST_PAGE_URL = "last_page_url"
        private const val CONSENT_GRANTED = "granted"
        private const val CONSENT_DENIED = "denied"
        private const val MAX_PENDING_EVENTS = 100
        private const val MAX_PENDING_CRASH_REPORTS = 10
        private const val MAX_BATCH_SIZE = 10
        private const val MAX_EVENT_TYPE = 64
        private const val MAX_TITLE = 256
        private const val MAX_CATEGORY = 80
        private const val MAX_NAME = 128
        private const val MAX_LANGUAGE = 35
        private const val MAX_VERSION = 24
        private const val SESSION_TIMEOUT_MS = 30 * 60 * 1000L
        private const val MIN_FLUSH_MS = 1_000L
        private const val MAX_FLUSH_MS = 60_000L

        private fun endpoint(apiOrigin: String): String {
            val origin = URI(apiOrigin.trim())
            require(origin.scheme.equals("https", ignoreCase = true)) { "apiOrigin must use HTTPS" }
            require(origin.host != null && origin.rawUserInfo == null && origin.rawQuery == null && origin.rawFragment == null) {
                "apiOrigin must be an HTTPS origin or base path without credentials, query, or fragment"
            }
            val basePath = origin.rawPath.trimEnd('/')
            return "${origin.scheme}://${origin.rawAuthority}$basePath/api/v1/collect"
        }

        private fun SeeRayAnalyticsOptions.validated(): SeeRayAnalyticsOptions {
            require(siteId.matches(Regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"))) { "siteId is invalid" }
            endpoint(apiOrigin)
            require(!flushInterval.isNegative && !flushInterval.isZero) { "flushInterval must be positive" }
            if (captureNativeCrashes) {
                require(appRelease?.matches(Regex("^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$")) == true) {
                    "appRelease must be set to an immutable 1-100 character release identifier when crash capture is enabled"
                }
                val crashUrl = validatedPageUrl(crashContextUrl)
                require(crashUrl != null && URI(crashUrl).scheme.equals("https", ignoreCase = true)) {
                    "crashContextUrl must be an HTTPS URL on an allowed domain when native crash capture is enabled"
                }
            }
            return copy(batchSize = batchSize.coerceIn(1, MAX_BATCH_SIZE))
        }

        private fun safeCrashPageUrl(value: String?): String? {
            val url = validatedPageUrl(value) ?: return null
            val uri = URI(url)
            return "${uri.scheme}://${uri.rawAuthority}${safeCrashPath(uri.rawPath?.ifEmpty { "/" } ?: "/")}"
        }

        private fun safeCrashPath(value: String): String = value
            .replace(Regex("[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}"), "<email>")
            .replace(Regex("(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\b"), "<id>")
            .replace(Regex("\\b(?:[A-Za-z0-9_-]{32,}|\\d{4,})\\b"), "<value>")
            .replace(Regex("[^A-Za-z0-9._~!$&'()*+,;=:@%/-]"), "_")
            .take(1024)

        private fun cleanErrorName(value: String): String = value
            .replace(Regex("[^A-Za-z0-9_.$-]"), "")
            .take(80)
            .ifBlank { "Error" }

        private fun sanitizeCrashMessage(value: String?): String {
            var clean = value.orEmpty().filterNot(Char::isISOControl).replace(Regex("\\s+"), " ").trim()
            clean = clean.replace(Regex("(?i)bearer\\s+[^\\s,;]+"), "Bearer <redacted>")
                .replace(
                    Regex("(?i)(api[_-]?key|token|secret|password)\\s*[:=]\\s*[^\\s,;]+"),
                    "${'$'}1=<redacted>",
                )
                .replace(Regex("https?://\\S+"), "<url>")
                .replace(Regex("[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}"), "<email>")
                .replace(
                    Regex("(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\b"),
                    "<id>",
                )
                .replace(Regex("(?:[A-Za-z]:\\\\|/(?:home|Users|tmp|var|opt)/)[^\\s:]+"), "<path>")
                .replace(Regex("\\b(?:[A-Za-z0-9_-]{32,}|\\d{4,})\\b"), "<value>")
            return clean.take(240).ifBlank { "No error message" }
        }

        private fun validatedPageUrl(value: String?): String? {
            if (value.isNullOrBlank() || value.length > 2048) return null
            return runCatching {
                URI(value).takeIf {
                    (it.scheme == "https" || it.scheme == "http") && it.host != null && it.rawUserInfo == null
                }?.let { uri ->
                    // Queries and fragments frequently contain search terms or account/reset tokens.
                    "${uri.scheme}://${uri.rawAuthority}${uri.rawPath?.ifEmpty { "/" } ?: "/"}"
                }
            }.getOrNull()
        }

        private fun cleanEventType(value: String): String? = value.trim().takeIf {
            it.length in 1..MAX_EVENT_TYPE && it.matches(Regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$"))
        }

        private fun boundedText(value: String?, max: Int): String? = value
            ?.filterNot { it.isISOControl() }
            ?.trim()
            ?.take(max)
            ?.takeIf(String::isNotEmpty)

        private fun cleanUserId(value: String?): String? = boundedText(value, 128)

        private fun cleanProperties(input: Map<String, Any?>): Map<String, Any> = input.entries
            .asSequence()
            .take(10)
            .mapNotNull { (key, value) ->
                val cleanKey = boundedText(key, 32) ?: return@mapNotNull null
                val cleanValue: Any = when (value) {
                    is String -> boundedText(value, 128) ?: return@mapNotNull null
                    is Boolean -> value
                    is Byte, is Short, is Int, is Long -> (value as Number).toLong()
                    is Float, is Double -> (value as Number).toDouble().takeIf(Double::isFinite) ?: return@mapNotNull null
                    else -> return@mapNotNull null
                }
                cleanKey to cleanValue
            }
            .toMap(LinkedHashMap())

        private fun jsonObject(fields: Map<String, Any?>): String = fields.entries
            .filter { it.value != null }
            .joinToString(prefix = "{", postfix = "}") { (key, value) -> "${jsonString(key)}:${jsonValue(value)}" }

        private fun jsonValue(value: Any?): String = when (value) {
            null -> "null"
            is JsonFragment -> value.value
            is String -> jsonString(value)
            is Number -> value.toString()
            is Boolean -> value.toString()
            is Map<*, *> -> jsonObject(value.entries.associate { it.key.toString() to it.value })
            is Iterable<*> -> value.joinToString(prefix = "[", postfix = "]") { jsonValue(it) }
            else -> error("Unsupported JSON value: ${value.javaClass.name}")
        }

        private fun jsonString(value: String): String = buildString(value.length + 2) {
            append('"')
            value.forEach { character ->
                when (character) {
                    '"' -> append("\\\"")
                    '\\' -> append("\\\\")
                    '\b' -> append("\\b")
                    '\u000c' -> append("\\f")
                    '\n' -> append("\\n")
                    '\r' -> append("\\r")
                    '\t' -> append("\\t")
                    else -> if (character.code < 0x20) append("\\u%04x".format(character.code)) else append(character)
                }
            }
            append('"')
        }
    }
}

internal interface AnalyticsStore {
    fun get(key: String): String?
    fun put(key: String, value: String)
    fun remove(key: String)
    fun saveNativeCrash(siteId: String, report: PendingNativeCrash) = Unit
    fun pendingNativeCrashes(siteId: String): List<PendingNativeCrash> = emptyList()
    fun removeNativeCrash(siteId: String, eventId: String) = Unit
    fun clearNativeCrashes(siteId: String) = Unit
}

internal data class PendingNativeCrash(
    val eventId: String,
    val occurredAt: String,
    val url: String,
    val errorName: String,
    val message: String,
    val sourcePath: String,
    val line: Int?,
    val functionName: String?,
    val releaseId: String?,
) {
    fun encode(): String = listOf(
        eventId,
        occurredAt,
        url,
        errorName,
        message,
        sourcePath,
        line?.toString().orEmpty(),
        functionName.orEmpty(),
        releaseId.orEmpty(),
    ).joinToString("\t")

    companion object {
        fun decode(value: String): PendingNativeCrash? {
            val fields = value.split('\t')
            if (fields.size != 9) return null
            return runCatching {
                PendingNativeCrash(
                    eventId = fields[0],
                    occurredAt = fields[1],
                    url = fields[2],
                    errorName = fields[3],
                    message = fields[4],
                    sourcePath = fields[5],
                    line = fields[6].toIntOrNull(),
                    functionName = fields[7].ifEmpty { null },
                    releaseId = fields[8].ifEmpty { null },
                ).takeIf {
                    runCatching { UUID.fromString(it.eventId) }.isSuccess
                        && runCatching { Instant.parse(it.occurredAt) }.isSuccess
                        && URI(it.url).scheme.equals("https", ignoreCase = true)
                }
            }.getOrNull()
        }
    }
}

internal interface AnalyticsTransport {
    fun post(endpoint: String, body: String): Boolean
}

private class AndroidAnalyticsStore(private val context: Context) : AnalyticsStore {
    private val preferences: SharedPreferences = context.getSharedPreferences("seeray_analytics", Context.MODE_PRIVATE)
    private val crashOutbox = NoBackupCrashOutbox(context.noBackupFilesDir)
    override fun get(key: String): String? = preferences.getString(key, null)
    override fun put(key: String, value: String) { preferences.edit().putString(key, value).apply() }
    override fun remove(key: String) { preferences.edit().remove(key).apply() }

    override fun saveNativeCrash(siteId: String, report: PendingNativeCrash) = crashOutbox.save(siteId, report)

    override fun pendingNativeCrashes(siteId: String): List<PendingNativeCrash> = crashOutbox.pending(siteId)

    override fun removeNativeCrash(siteId: String, eventId: String) = crashOutbox.remove(siteId, eventId)

    override fun clearNativeCrashes(siteId: String) = crashOutbox.clear(siteId)
}

/** Durable outbox deliberately lives outside Android auto-backup and excludes raw stack traces. */
internal class NoBackupCrashOutbox(private val noBackupFilesDir: File) {
    fun save(siteId: String, report: PendingNativeCrash) {
        val directory = crashDirectory(siteId)
        if (!directory.isDirectory && !directory.mkdirs()) return
        val existing = directory.listFiles { file -> file.name.endsWith(".crash") }.orEmpty()
        if (existing.size >= 10) return
        val time = runCatching { Instant.parse(report.occurredAt).toEpochMilli() }.getOrDefault(0L)
        val target = File(directory, "%013d--%s.crash".format(Locale.ROOT, time, report.eventId))
        val temporary = File(directory, ".${report.eventId}.tmp")
        try {
            FileOutputStream(temporary).use { stream ->
                stream.write(report.encode().toByteArray(StandardCharsets.UTF_8))
                stream.fd.sync()
            }
            if (!temporary.renameTo(target)) temporary.delete()
        } catch (_: Exception) {
            temporary.delete()
        }
    }

    fun pending(siteId: String): List<PendingNativeCrash> {
        val directory = crashDirectory(siteId)
        directory.listFiles { file -> file.name.endsWith(".tmp") }.orEmpty().forEach(File::delete)
        return directory.listFiles { file -> file.name.endsWith(".crash") }
            .orEmpty()
            .sortedBy(File::getName)
            .mapNotNull { file ->
                val report = runCatching {
                    PendingNativeCrash.decode(file.readText(StandardCharsets.UTF_8))
                }.getOrNull()
                if (report == null) file.delete()
                report
            }
    }

    fun remove(siteId: String, eventId: String) {
        crashDirectory(siteId).listFiles { file -> file.name.endsWith("--$eventId.crash") }
            .orEmpty().forEach(File::delete)
    }

    fun clear(siteId: String) {
        crashDirectory(siteId).listFiles().orEmpty().forEach(File::delete)
    }

    private fun crashDirectory(siteId: String): File {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(siteId.toByteArray(StandardCharsets.UTF_8))
            .take(16)
            .joinToString("") { "%02x".format(Locale.ROOT, it) }
        return File(File(noBackupFilesDir, "seeray-analytics-crashes"), digest)
    }
}

private class UrlConnectionAnalyticsTransport : AnalyticsTransport {
    override fun post(endpoint: String, body: String): Boolean {
        val connection = URL(endpoint).openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 5_000
            connection.readTimeout = 5_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            connection.setFixedLengthStreamingMode(body.toByteArray(StandardCharsets.UTF_8).size)
            connection.outputStream.use { it.write(body.toByteArray(StandardCharsets.UTF_8)) }
            connection.responseCode in 200..299
        } finally {
            connection.disconnect()
        }
    }
}
