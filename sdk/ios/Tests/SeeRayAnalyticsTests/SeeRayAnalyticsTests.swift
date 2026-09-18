import Foundation
import XCTest
@testable import SeeRayAnalytics

final class SeeRayAnalyticsTests: XCTestCase {
    func testRequiredConsentDoesNotPersistIdentityOrSendEventsUntilAccepted() async throws {
        let store = MemoryStorage()
        let transport = RecordingTransport()
        let analytics = try makeAnalytics(
            store: store,
            transport: transport,
            requireConsent: true
        )

        await analytics.trackScreen(name: "pricing", url: "https://shop.example/pricing")
        let initialState = await analytics.consentState()
        let initialQueueSize = await analytics.queuedEventCount()
        let initialVisitorId = store.string(forKey: "seeray:srl_ios_test:visitor_id")
        let emptyFlush = await analytics.flush()
        let payloads = await transport.payloads()

        XCTAssertEqual(initialState, .unknown)
        XCTAssertEqual(initialQueueSize, 0)
        XCTAssertNil(initialVisitorId)
        XCTAssertTrue(emptyFlush)
        XCTAssertEqual(payloads.count, 0)
    }

    func testConsentPersistsIdentityAndSendsMinimizedScreenEvent() async throws {
        let store = MemoryStorage()
        let transport = RecordingTransport()
        let analytics = try makeAnalytics(store: store, transport: transport, requireConsent: true)

        await analytics.setConsent(granted: true)
        await analytics.trackScreen(
            name: "Pricing",
            url: "https://shop.example/pricing?email=private@example.test#signup"
        )
        let sent = await analytics.flush()
        let visitorId = store.string(forKey: "seeray:srl_ios_test:visitor_id")
        let sessionId = store.string(forKey: "seeray:srl_ios_test:session_id")
        let payloads = await transport.payloads()
        let payload = try XCTUnwrap(payloads.first)
        let batch = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let events = try XCTUnwrap(batch["events"] as? [[String: Any]])
        let event = try XCTUnwrap(events.first)
        let properties = try XCTUnwrap(event["properties"] as? [String: String])
        let context = try XCTUnwrap(event["context"] as? [String: String])

        XCTAssertTrue(sent)
        XCTAssertEqual(store.string(forKey: "seeray:srl_ios_test:consent"), "granted")
        XCTAssertNotNil(visitorId)
        XCTAssertNotNil(sessionId)
        XCTAssertEqual(batch["schemaVersion"] as? Int, 1)
        XCTAssertEqual(batch["siteId"] as? String, "srl_ios_test")
        XCTAssertEqual(event["type"] as? String, "page_view")
        XCTAssertEqual(event["url"] as? String, "https://shop.example/pricing")
        XCTAssertEqual(event["title"] as? String, "Pricing")
        XCTAssertEqual(event["visitorId"] as? String, visitorId)
        XCTAssertEqual(event["sessionId"] as? String, sessionId)
        XCTAssertEqual(properties["screen"], "Pricing")
        XCTAssertEqual(context["operatingSystem"], "iOS")
        XCTAssertEqual(context["deviceType"], "mobile")
        XCTAssertFalse(String(data: payload, encoding: .utf8)?.contains("private@example.test") ?? true)
    }

    func testWithdrawalClearsQueuedEventsAndSDKOwnedIdentifiers() async throws {
        let store = MemoryStorage()
        let transport = RecordingTransport()
        let analytics = try makeAnalytics(store: store, transport: transport, requireConsent: true)

        await analytics.setConsent(granted: true)
        await analytics.trackEvent(
            type: "signup",
            url: "https://shop.example/signup",
            properties: ["plan": .string("pro")]
        )
        await analytics.setConsent(granted: false)
        let state = await analytics.consentState()
        let queuedCount = await analytics.queuedEventCount()
        let flush = await analytics.flush()
        let payloads = await transport.payloads()

        XCTAssertEqual(state, .denied)
        XCTAssertEqual(queuedCount, 0)
        XCTAssertTrue(flush)
        XCTAssertEqual(store.string(forKey: "seeray:srl_ios_test:consent"), "denied")
        XCTAssertNil(store.string(forKey: "seeray:srl_ios_test:visitor_id"))
        XCTAssertNil(store.string(forKey: "seeray:srl_ios_test:session_id"))
        XCTAssertNil(store.string(forKey: "seeray:srl_ios_test:session_last_activity"))
        XCTAssertTrue(payloads.isEmpty)
    }

    func testFailedBatchIsRetriedWithoutChangingEventIdentity() async throws {
        let transport = RecordingTransport()
        await transport.failNextRequest()
        let analytics = try makeAnalytics(
            store: MemoryStorage(),
            transport: transport,
            requireConsent: false
        )

        await analytics.trackGoal(name: "signup_complete", url: "https://shop.example/done")
        let firstSend = await analytics.flush()
        let queuedAfterFailure = await analytics.queuedEventCount()
        let secondSend = await analytics.flush()
        let payloads = await transport.payloads()
        let firstId = try eventId(in: payloads[0])
        let secondId = try eventId(in: payloads[1])

        XCTAssertFalse(firstSend)
        XCTAssertEqual(queuedAfterFailure, 1)
        XCTAssertTrue(secondSend)
        XCTAssertEqual(firstId, secondId)
    }

    func testSessionRotatesAfterThirtyMinutesWithoutReplacingVisitorId() async throws {
        let store = MemoryStorage()
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let analytics = try SeeRayAnalytics(
            options: SeeRayAnalyticsOptions(
                siteId: "srl_ios_test",
                apiOrigin: "https://analytics.example.test",
                flushInterval: 60
            ),
            storage: store,
            transport: RecordingTransport(),
            now: { clock.now() }
        )

        await analytics.trackPageView(url: "https://shop.example/first")
        let firstVisitor = store.string(forKey: "seeray:srl_ios_test:visitor_id")
        let firstSession = store.string(forKey: "seeray:srl_ios_test:session_id")
        clock.advance(by: 30 * 60 + 1)
        await analytics.trackPageView(url: "https://shop.example/second")
        let secondVisitor = store.string(forKey: "seeray:srl_ios_test:visitor_id")
        let secondSession = store.string(forKey: "seeray:srl_ios_test:session_id")

        XCTAssertEqual(firstVisitor, secondVisitor)
        XCTAssertNotEqual(firstSession, secondSession)
    }

    func testRejectsPlaintextCollectorOriginsAndInvalidSiteIds() {
        XCTAssertThrowsError(
            try SeeRayAnalyticsOptions(siteId: "srl_ios_test", apiOrigin: "http://analytics.example")
                .makeForValidation()
        )
        XCTAssertThrowsError(
            try SeeRayAnalytics(
                options: SeeRayAnalyticsOptions(siteId: "bad id", apiOrigin: "https://analytics.example"),
                storage: MemoryStorage(),
                transport: RecordingTransport()
            )
        )
    }

    private func makeAnalytics(
        store: MemoryStorage,
        transport: RecordingTransport,
        requireConsent: Bool
    ) throws -> SeeRayAnalytics {
        try SeeRayAnalytics(
            options: SeeRayAnalyticsOptions(
                siteId: "srl_ios_test",
                apiOrigin: "https://analytics.example.test/edge",
                requireConsent: requireConsent,
                flushInterval: 60
            ),
            storage: store,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private func eventId(in payload: Data) throws -> String {
        let batch = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let events = try XCTUnwrap(batch["events"] as? [[String: Any]])
        return try XCTUnwrap(events.first?["eventId"] as? String)
    }
}

private final class MemoryStorage: SeeRayAnalyticsStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func removeValue(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date.addTimeInterval(interval)
    }
}

private actor RecordingTransport: SeeRayAnalyticsTransport {
    private var sent: [Data] = []
    private var failRequests = 0

    func send(_ body: Data, to endpoint: URL) async throws {
        guard endpoint.absoluteString == "https://analytics.example.test/edge/api/v1/collect" else {
            throw URLError(.badURL)
        }
        sent.append(body)
        if failRequests > 0 {
            failRequests -= 1
            throw URLError(.timedOut)
        }
    }

    func failNextRequest() { failRequests += 1 }
    func payloads() -> [Data] { sent }
}

private extension SeeRayAnalyticsOptions {
    func makeForValidation() throws -> SeeRayAnalytics {
        try SeeRayAnalytics(options: self, storage: MemoryStorage(), transport: RecordingTransport())
    }
}
