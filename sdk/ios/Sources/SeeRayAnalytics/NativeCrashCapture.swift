import Foundation

struct SeeRayPendingNativeCrash: Codable, Sendable {
    let eventId: String
    let occurredAt: String
    let url: String
    let errorName: String
    let message: String
    let sourcePath: String
    let functionName: String?
    let releaseId: String

    func trackingEvent(context: SeeRayEventContext) -> SeeRayTrackingEvent {
        var properties: [String: SeeRayValue] = [
            "platform": .string("ios"),
            "message": .string(message),
            "sourcePath": .string(sourcePath),
        ]
        if let functionName { properties["functionName"] = .string(functionName) }
        properties["releaseId"] = .string(releaseId)
        return SeeRayTrackingEvent(
            eventId: eventId,
            type: "client_error",
            occurredAt: occurredAt,
            url: url,
            title: nil,
            referrer: nil,
            visitorId: nil,
            sessionId: nil,
            userId: nil,
            category: "error",
            action: "native_ios",
            name: errorName,
            properties: properties,
            context: context,
            pendingCrashId: eventId
        )
    }

    func isValid() -> Bool {
        guard UUID(uuidString: eventId) != nil,
              ISO8601DateFormatter().date(from: occurredAt) != nil,
              let components = URLComponents(string: url),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil,
              !errorName.isEmpty,
              !releaseId.isEmpty
        else { return false }
        return true
    }
}

/// Bounded diagnostics spool in Caches, which is excluded from iOS backups.
final class SeeRayNativeCrashOutbox: @unchecked Sendable {
    private static let maximumReports = 10
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        #if os(iOS)
            markExcludedFromBackup(self.rootDirectory)
        #endif
    }

    func save(siteId: String, report: SeeRayPendingNativeCrash) {
        guard report.isValid() else { return }
        lock.lock()
        defer { lock.unlock() }

        let directory = siteDirectory(siteId)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
                markExcludedFromBackup(directory)
            #endif
            let existing = try crashFiles(in: directory)
            guard existing.count < Self.maximumReports else { return }

            let target = directory.appendingPathComponent("\(report.eventId).crash")
            let temporary = directory.appendingPathComponent(".\(report.eventId).tmp")
            let data = try JSONEncoder().encode(report)
            guard fileManager.createFile(atPath: temporary.path, contents: nil) else { return }
            do {
                let handle = try FileHandle(forWritingTo: temporary)
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
                try fileManager.moveItem(at: temporary, to: target)
                #if os(iOS)
                    markExcludedFromBackup(target)
                #endif
            } catch {
                try? fileManager.removeItem(at: temporary)
            }
        } catch {
            return
        }
    }

    func pending(siteId: String) -> [SeeRayPendingNativeCrash] {
        lock.lock()
        defer { lock.unlock() }
        let directory = siteDirectory(siteId)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var reports: [SeeRayPendingNativeCrash] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if file.pathExtension == "tmp" {
                try? fileManager.removeItem(at: file)
                continue
            }
            guard file.pathExtension == "crash",
                  let data = try? Data(contentsOf: file),
                  let report = try? JSONDecoder().decode(SeeRayPendingNativeCrash.self, from: data),
                  report.isValid()
            else {
                try? fileManager.removeItem(at: file)
                continue
            }
            reports.append(report)
        }
        return Array(reports.prefix(Self.maximumReports))
    }

    func remove(siteId: String, eventId: String) {
        guard UUID(uuidString: eventId) != nil else { return }
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: siteDirectory(siteId).appendingPathComponent("\(eventId).crash"))
    }

    func clear(siteId: String) {
        lock.lock()
        defer { lock.unlock() }
        let directory = siteDirectory(siteId)
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "crash" || file.pathExtension == "tmp" {
            try? fileManager.removeItem(at: file)
        }
    }

    private func siteDirectory(_ siteId: String) -> URL {
        rootDirectory
            .appendingPathComponent("seeray-native-crashes", isDirectory: true)
            .appendingPathComponent(siteId, isDirectory: true)
    }

    private func crashFiles(in directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "crash" }
    }

    #if os(iOS)
        private func markExcludedFromBackup(_ url: URL) {
            var value = URLResourceValues()
            value.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(value)
        }
    #endif
}

struct SeeRayNativeCrashRegistration: Sendable {
    let id: UUID
    let options: SeeRayAnalyticsOptions
    let storage: SeeRayAnalyticsStorage
    let outbox: SeeRayNativeCrashOutbox
}

enum SeeRayNativeCrashPrivacy {
    static func safePageURL(_ value: String) -> String {
        guard var components = URLComponents(string: value),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil
        else { return "https://invalid.invalid/" }
        components.query = nil
        components.fragment = nil
        components.path = scrubPath(components.path)
        return components.string ?? "https://invalid.invalid/"
    }

    static func safeMessage(_ value: String?) -> String {
        var message = value?.replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        message = redact(message, #"(?i)bearer\s+[^\s,;]+"#, "Bearer <redacted>")
        message = redact(message, #"(?i)(api[_-]?key|token|secret|password)\s*[:=]\s*[^\s,;]+"#, "$1=<redacted>")
        message = redact(message, #"https?://\S+"#, "<url>")
        message = redact(message, #"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#, "<email>")
        message = redact(message, #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#, "<id>")
        message = redact(message, #"(?:[A-Za-z]:\\|/(?:Users|home|private|tmp|var|opt)/)[^\s:]+"#, "<path>")
        message = redact(message, #"\b(?:[A-Za-z0-9_-]{32,}|\d{4,})\b"#, "<value>")
        return String((message.isEmpty ? "No error message" : message).prefix(240))
    }

    static func safeErrorName(_ value: String) -> String {
        let safe = String(value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "_.$-".contains($0)) }.prefix(80))
        return safe.isEmpty ? "Exception" : safe
    }

    static func safeFunctionName(_ value: String?) -> String? {
        guard let value else { return nil }
        var safe = value.replacingOccurrences(of: #"0x[0-9a-fA-F]+"#, with: "<address>", options: .regularExpression)
        safe = redact(safe, #"(?:[A-Za-z]:\\|/(?:Users|home|private|tmp|var|opt)/)[^\s:]+"#, "<path>")
        safe = safe.replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
        let trimmed = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(240))
    }

    static func capture(
        registration: SeeRayNativeCrashRegistration,
        errorName: String,
        message: String?,
        functionName: String?,
        occurredAt: Date = Date()
    ) {
        let storage = registration.storage
        let analyticsConsent = storage.string(forKey: "seeray:\(registration.options.siteId):consent")
        let allowedBySite = analyticsConsent == SeeRayConsentState.granted.rawValue
            || (analyticsConsent == nil && !registration.options.requireConsent)
        guard registration.options.captureNativeCrashes,
              allowedBySite,
              storage.string(forKey: "seeray:\(registration.options.siteId):native_crash_consent")
                  == SeeRayConsentState.granted.rawValue,
              let fallback = registration.options.crashContextURL
        else { return }

        let savedURL = storage.string(forKey: "seeray:\(registration.options.siteId):last_screen_url")
        let url = safePageURL(savedURL ?? fallback)
        let report = SeeRayPendingNativeCrash(
            eventId: UUID().uuidString.lowercased(),
            occurredAt: seeRayTimestamp(occurredAt),
            url: url,
            errorName: safeErrorName(errorName),
            message: safeMessage(message),
            sourcePath: "ios-native",
            functionName: safeFunctionName(functionName),
            releaseId: registration.options.appRelease ?? ""
        )
        registration.outbox.save(siteId: registration.options.siteId, report: report)
    }

    private static func scrubPath(_ value: String) -> String {
        var path = redact(value, #"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#, "<email>")
        path = redact(path, #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#, "<id>")
        path = redact(path, #"(^|/)\d{4,}(?=/|$)"#, "$1<id>")
        return redact(path, #"(^|/)[A-Za-z0-9_-]{32,}(?=/|$)"#, "$1<id>")
    }

    private static func redact(_ value: String, _ pattern: String, _ replacement: String) -> String {
        value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}

final class SeeRayNativeCrashRegistry: @unchecked Sendable {
    static let shared = SeeRayNativeCrashRegistry()

    private let lock = NSLock()
    private var registrations: [UUID: SeeRayNativeCrashRegistration] = [:]
    #if os(iOS)
        private var previousHandler: (@convention(c) (NSException) -> Void)?
        private var handlerInstalled = false

        private static let exceptionHandler: @convention(c) (NSException) -> Void = { exception in
            SeeRayNativeCrashRegistry.shared.handle(exception)
        }
    #endif

    func register(_ registration: SeeRayNativeCrashRegistration) {
        lock.lock()
        defer { lock.unlock() }
        registrations[registration.id] = registration
        #if os(iOS)
            if !handlerInstalled {
                previousHandler = NSGetUncaughtExceptionHandler()
                NSSetUncaughtExceptionHandler(Self.exceptionHandler)
                handlerInstalled = true
            }
        #endif
    }

    func unregister(_ id: UUID) {
        lock.lock()
        registrations.removeValue(forKey: id)
        lock.unlock()
    }

    func captureForTesting(
        registrationID: UUID,
        errorName: String,
        message: String?,
        functionName: String?,
        occurredAt: Date = Date()
    ) {
        lock.lock()
        let registration = registrations[registrationID]
        lock.unlock()
        guard let registration else { return }
        SeeRayNativeCrashPrivacy.capture(
            registration: registration,
            errorName: errorName,
            message: message,
            functionName: functionName,
            occurredAt: occurredAt
        )
    }

    #if os(iOS)
        private func handle(_ exception: NSException) {
            lock.lock()
            let configured = Array(registrations.values)
            let previous = previousHandler
            lock.unlock()

            let name = exception.name.rawValue
            let message = exception.reason
            let frame = exception.callStackSymbols.first { !$0.contains("SeeRayAnalytics") }
            for registration in configured {
                SeeRayNativeCrashPrivacy.capture(
                    registration: registration,
                    errorName: name,
                    message: message,
                    functionName: frame
                )
            }
            previous?(exception)
        }
    #endif
}
