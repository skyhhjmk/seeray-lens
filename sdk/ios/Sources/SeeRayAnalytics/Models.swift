import Foundation

public struct SeeRayAnalyticsOptions: Sendable {
    public let siteId: String
    public let apiOrigin: String
    public let requireConsent: Bool
    public let batchSize: Int
    public let flushInterval: TimeInterval
    public let captureNativeCrashes: Bool
    public let appRelease: String?
    public let crashContextURL: String?

    public init(
        siteId: String,
        apiOrigin: String,
        requireConsent: Bool = false,
        batchSize: Int = 10,
        flushInterval: TimeInterval = 10,
        captureNativeCrashes: Bool = false,
        appRelease: String? = nil,
        crashContextURL: String? = nil
    ) {
        self.siteId = siteId
        self.apiOrigin = apiOrigin
        self.requireConsent = requireConsent
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.captureNativeCrashes = captureNativeCrashes
        self.appRelease = appRelease
        self.crashContextURL = crashContextURL
    }
}

public enum SeeRayAnalyticsError: Error, Equatable {
    case invalidSiteId
    case invalidAPIOrigin
    case invalidFlushInterval
    case invalidNativeCrashConfiguration
}

public enum SeeRayConsentState: String, Sendable {
    case unknown
    case granted
    case denied
}

/// JSON scalar allowed in a custom event property. Nested objects and arrays are not accepted.
public enum SeeRayValue: Sendable, Codable, Equatable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case boolean(Bool)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let boolean = try? value.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let integer = try? value.decode(Int64.self) {
            self = .integer(integer)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.typeMismatch(
                SeeRayValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected a JSON scalar")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let string): try value.encode(string)
        case .integer(let integer): try value.encode(integer)
        case .number(let number): try value.encode(number)
        case .boolean(let boolean): try value.encode(boolean)
        }
    }

    var bounded: SeeRayValue? {
        switch self {
        case .string(let value):
            return value.count <= 1_000 ? self : nil
        case .number(let value):
            return value.isFinite ? self : nil
        case .integer, .boolean:
            return self
        }
    }
}

struct SeeRayEventContext: Encodable, Sendable {
    let browser: String
    let operatingSystem: String
    let operatingSystemVersion: String
    let deviceType: String
    let language: String
}

struct SeeRayTrackingEvent: Encodable, Sendable {
    let eventId: String
    let type: String
    let occurredAt: String
    let url: String
    let title: String?
    let referrer: String?
    let visitorId: String?
    let sessionId: String?
    let userId: String?
    let category: String?
    let action: String?
    let name: String?
    let properties: [String: SeeRayValue]?
    let context: SeeRayEventContext
    let pendingCrashId: String?

    private enum CodingKeys: String, CodingKey {
        case eventId
        case type
        case occurredAt
        case url
        case title
        case referrer
        case visitorId
        case sessionId
        case userId
        case category
        case action
        case name
        case properties
        case context
    }
}

struct SeeRayTrackingBatch: Encodable, Sendable {
    let schemaVersion: Int
    let siteId: String
    let sentAt: String
    let events: [SeeRayTrackingEvent]
}

func seeRayTimestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
