import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(UIKit)
    import UIKit
#endif

protocol SeeRayAnalyticsStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeValue(forKey key: String)
}

protocol SeeRayAnalyticsTransport: Sendable {
    func send(_ body: Data, to endpoint: URL) async throws
}

private final class UserDefaultsStorage: SeeRayAnalyticsStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(value, forKey: key)
    }

    func removeValue(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}

private final class URLSessionTransport: SeeRayAnalyticsTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func send(_ body: Data, to endpoint: URL) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
    }
}

/// Explicit, consent-aware analytics for native iOS applications.
///
/// The SDK does not infer navigation, crashes, device models, advertising IDs, or user identity.
/// The host app decides when a screen becomes visible and when its conversion actually succeeds.
public actor SeeRayAnalytics {
    private static let maximumBatchSize = 10
    private static let maximumQueuedEvents = 100
    private static let sessionTimeout: TimeInterval = 30 * 60

    private let options: SeeRayAnalyticsOptions
    private let endpoint: URL
    private let storage: SeeRayAnalyticsStorage
    private let transport: SeeRayAnalyticsTransport
    private let now: @Sendable () -> Date
    private let batchSize: Int
    private let flushInterval: TimeInterval

    private var pending: [SeeRayTrackingEvent] = []
    private var flushTask: Task<Void, Never>?
    private var userId: String?
    private var closed = false
    private var droppedEventCount = 0

    public init(options: SeeRayAnalyticsOptions) throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        try self.init(
            options: options,
            storage: UserDefaultsStorage(defaults: .standard),
            transport: URLSessionTransport(session: URLSession(configuration: configuration)),
            now: { Date() }
        )
    }

    init(
        options: SeeRayAnalyticsOptions,
        storage: SeeRayAnalyticsStorage,
        transport: SeeRayAnalyticsTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        guard options.siteId.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#,
            options: .regularExpression
        ) != nil else {
            throw SeeRayAnalyticsError.invalidSiteId
        }
        guard options.flushInterval.isFinite, options.flushInterval > 0 else {
            throw SeeRayAnalyticsError.invalidFlushInterval
        }
        guard let endpoint = Self.endpoint(for: options.apiOrigin) else {
            throw SeeRayAnalyticsError.invalidAPIOrigin
        }

        self.options = options
        self.endpoint = endpoint
        self.storage = storage
        self.transport = transport
        self.now = now
        self.batchSize = min(max(options.batchSize, 1), Self.maximumBatchSize)
        self.flushInterval = min(max(options.flushInterval, 0.2), 60)
    }

    public func consentState() -> SeeRayConsentState {
        if let saved = storage.string(forKey: consentKey),
           let state = SeeRayConsentState(rawValue: saved), state != .unknown
        {
            return state
        }
        return options.requireConsent ? .unknown : .granted
    }

    /// Apply the visitor's choice. Denial immediately clears queued events and SDK-owned IDs.
    public func setConsent(granted: Bool) {
        guard !closed else { return }
        storage.set(granted ? SeeRayConsentState.granted.rawValue : SeeRayConsentState.denied.rawValue,
                    forKey: consentKey)
        guard !granted else { return }

        pending.removeAll(keepingCapacity: false)
        flushTask?.cancel()
        flushTask = nil
        userId = nil
        storage.removeValue(forKey: visitorKey)
        storage.removeValue(forKey: sessionKey)
        storage.removeValue(forKey: lastActivityKey)
    }

    /// Store an opaque application account ID for subsequent consented events only.
    public func setUserId(_ value: String?) {
        guard !closed, consentState() == .granted else {
            userId = nil
            return
        }
        userId = Self.cleanText(value, maximumLength: 256)
    }

    public func trackPageView(url: String, title: String? = nil, referrer: String? = nil) {
        record(type: "page_view", url: url, title: title, referrer: referrer)
    }

    public func trackScreen(
        name: String,
        url: String,
        title: String? = nil,
        referrer: String? = nil
    ) {
        let screen = Self.cleanText(name, maximumLength: 120)
        guard let screen else { return }
        record(
            type: "page_view",
            url: url,
            title: title ?? screen,
            referrer: referrer,
            properties: ["screen": .string(screen)]
        )
    }

    public func trackEvent(
        type: String,
        url: String,
        category: String? = nil,
        action: String? = nil,
        name: String? = nil,
        properties: [String: SeeRayValue] = [:],
        title: String? = nil,
        referrer: String? = nil
    ) {
        record(
            type: type,
            url: url,
            title: title,
            referrer: referrer,
            category: category,
            action: action,
            name: name,
            properties: properties
        )
    }

    public func trackGoal(
        name: String,
        url: String,
        properties: [String: SeeRayValue] = [:],
        title: String? = nil
    ) {
        record(type: "goal", url: url, title: title, name: name, properties: properties)
    }

    /// Sends at most one bounded batch. Failed batches are requeued for a later flush.
    @discardableResult
    public func flush() async -> Bool {
        flushTask?.cancel()
        flushTask = nil
        guard consentState() == .granted else {
            pending.removeAll(keepingCapacity: false)
            return true
        }
        guard !pending.isEmpty else { return true }

        let count = min(batchSize, pending.count)
        let batchEvents = Array(pending.prefix(count))
        pending.removeFirst(count)
        let body = SeeRayTrackingBatch(
            schemaVersion: 1,
            siteId: options.siteId,
            sentAt: seeRayTimestamp(now()),
            events: batchEvents
        )

        do {
            let encoder = JSONEncoder()
            try await transport.send(encoder.encode(body), to: endpoint)
            storage.set(String(now().timeIntervalSince1970), forKey: lastActivityKey)
            if !pending.isEmpty, !closed { scheduleFlush() }
            return true
        } catch {
            guard consentState() == .granted else { return false }
            pending.insert(contentsOf: batchEvents, at: 0)
            if !closed { scheduleFlush() }
            return false
        }
    }

    /// Stop automatic scheduling and make one best-effort final send.
    public func close() async {
        guard !closed else { return }
        closed = true
        flushTask?.cancel()
        flushTask = nil
        _ = await flush()
    }

    public func queuedEventCount() -> Int { pending.count }
    public func droppedEventCountValue() -> Int { droppedEventCount }

    private func record(
        type: String,
        url: String,
        title: String?,
        referrer: String? = nil,
        category: String? = nil,
        action: String? = nil,
        name: String? = nil,
        properties: [String: SeeRayValue] = [:]
    ) {
        guard !closed, consentState() == .granted,
              let eventType = Self.cleanText(type, maximumLength: 64),
              let pageURL = Self.minimizedURL(url)
        else { return }
        guard pending.count < Self.maximumQueuedEvents else {
            droppedEventCount += 1
            return
        }

        let date = now()
        let identity = ensureIdentity(at: date)
        let cleanProperties = cleanProperties(properties)
        pending.append(
            SeeRayTrackingEvent(
                eventId: UUID().uuidString.lowercased(),
                type: eventType,
                occurredAt: seeRayTimestamp(date),
                url: pageURL,
                title: Self.cleanText(title, maximumLength: 256),
                referrer: referrer.flatMap(Self.minimizedURL),
                visitorId: identity.visitor,
                sessionId: identity.session,
                userId: userId,
                category: Self.cleanText(category, maximumLength: 120),
                action: Self.cleanText(action, maximumLength: 120),
                name: Self.cleanText(name, maximumLength: 120),
                properties: cleanProperties.isEmpty ? nil : cleanProperties,
                context: Self.context()
            )
        )
        scheduleFlush(immediate: pending.count >= batchSize)
    }

    private func ensureIdentity(at date: Date) -> (visitor: String, session: String) {
        let visitor = storage.string(forKey: visitorKey) ?? UUID().uuidString.lowercased()
        storage.set(visitor, forKey: visitorKey)

        let previousActivity = storage.string(forKey: lastActivityKey).flatMap(TimeInterval.init)
        let existingSession = storage.string(forKey: sessionKey)
        let elapsed = previousActivity.map { date.timeIntervalSince1970 - $0 }
        let rotate = existingSession == nil || elapsed == nil || (elapsed ?? 0) >= Self.sessionTimeout || (elapsed ?? 0) < 0
        let session = rotate ? UUID().uuidString.lowercased() : existingSession!
        storage.set(session, forKey: sessionKey)
        storage.set(String(date.timeIntervalSince1970), forKey: lastActivityKey)
        return (visitor, session)
    }

    private func scheduleFlush(immediate: Bool = false) {
        guard !closed, flushTask == nil else { return }
        let delay = immediate ? 0 : flushInterval
        let nanoseconds = UInt64(min(delay, 60) * 1_000_000_000)
        flushTask = Task { [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.scheduledFlush()
        }
    }

    private func scheduledFlush() async {
        flushTask = nil
        _ = await flush()
    }

    private func cleanProperties(_ values: [String: SeeRayValue]) -> [String: SeeRayValue] {
        var result: [String: SeeRayValue] = [:]
        for (key, value) in values.prefix(30) {
            guard let cleanKey = Self.cleanText(key, maximumLength: 64),
                  let cleanValue = value.bounded
            else { continue }
            result[cleanKey] = cleanValue
        }
        return result
    }

    private static func cleanText(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let scalars = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maximumLength))
    }

    private static func minimizedURL(_ value: String) -> String? {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil,
              components.user == nil,
              components.password == nil
        else { return nil }
        components.query = nil
        components.fragment = nil
        guard let minimized = components.string, minimized.count <= 2_048 else { return nil }
        return minimized
    }

    private static func context() -> SeeRayEventContext {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #if canImport(UIKit)
            let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile"
        #else
            let deviceType = "mobile"
        #endif
        let language = Locale.preferredLanguages.first?.replacingOccurrences(of: "_", with: "-") ?? "und"
        return SeeRayEventContext(
            browser: "Other",
            operatingSystem: "iOS",
            operatingSystemVersion: String(osVersion.prefix(40)),
            deviceType: deviceType,
            language: String(language.prefix(40))
        )
    }

    private static func endpoint(for apiOrigin: String) -> URL? {
        guard var components = URLComponents(string: apiOrigin),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { return nil }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "api/v1/collect"].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url
    }

    private var consentKey: String { "seeray:\(options.siteId):consent" }
    private var visitorKey: String { "seeray:\(options.siteId):visitor_id" }
    private var sessionKey: String { "seeray:\(options.siteId):session_id" }
    private var lastActivityKey: String { "seeray:\(options.siteId):session_last_activity" }
}
