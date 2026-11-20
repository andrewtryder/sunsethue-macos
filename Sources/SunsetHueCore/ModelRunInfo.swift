import Foundation

/// Published forecast-run metadata. Run identifiers are opaque and compared verbatim.
public struct ModelRunInfo: Equatable, Sendable {
    public let identifier: String
    public let nextExpectedUpdate: Date?

    public init(identifier: String, nextExpectedUpdate: Date?) {
        self.identifier = identifier
        self.nextExpectedUpdate = nextExpectedUpdate
    }
}

/// The provider supplies run metadata in event responses and via /run-info.
/// Unknown or incomplete shapes are deliberately ignored; existing TTL behavior remains available.
enum ModelRunInfoParser {
    static func parse(_ data: Data) throws -> ModelRunInfo {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = parseOptional(object)
        else {
            throw SunsetHueError.invalidResponse("invalid_run_info")
        }
        return info
    }

    static func parseOptional(_ payload: [String: Any]) -> ModelRunInfo? {
        let root = (payload["data"] as? [String: Any]) ?? payload
        let runs = root["runs"] as? [String: Any]
        let current = (root["current_run"] as? [String: Any])
            ?? (root["current"] as? [String: Any])
            ?? (root["run"] as? [String: Any])
            ?? (root["last_run"] as? [String: Any])
            ?? (runs?["current"] as? [String: Any])

        let identifier = identifier(in: payload, includeNestedID: false)
            ?? identifier(in: root, includeNestedID: false)
            ?? identifier(in: current ?? [:], includeNestedID: true)
        guard let identifier else { return nil }

        let next = (root["next_run"] as? [String: Any])
            ?? (root["next"] as? [String: Any])
            ?? (runs?["next"] as? [String: Any])

        let expected = nextUpdate(in: root, nested: false)
            ?? nextUpdate(in: next ?? [:], nested: true)
            ?? nextUpdate(in: payload, nested: false)
        return ModelRunInfo(identifier: identifier, nextExpectedUpdate: expected)
    }

    private static func identifier(in object: [String: Any], includeNestedID: Bool) -> String? {
        let keys = ["run_id", "run_identifier", "runId", "current_run_id", "model_run", "current_run", "run"]
        for key in keys {
            if let value = object[key] as? String, let identifier = validated(value) {
                return identifier
            }
        }
        if includeNestedID {
            for key in ["id", "identifier", "name"] {
                if let value = object[key] as? String, let identifier = validated(value) {
                    return identifier
                }
            }
        }
        return nil
    }

    private static func validated(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 128 else { return nil }
        return value
    }

    private static func nextUpdate(in object: [String: Any], nested: Bool) -> Date? {
        let keys = nested
            ? ["expected_update", "expected_update_time", "expected_at", "update_time", "time", "at"]
            : ["next_expected_update", "next_expected_update_time", "next_update", "next_update_time",
               "next_update_at", "next_run_time", "next_run_expected_update"]
        for key in keys {
            if let value = object[key] as? String, let date = try? ResponseParser.parseDateTime(value) {
                return date
            }
        }
        return nil
    }
}

public struct ModelRunInfoService: Sendable {
    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetch(apiKey: String) async throws -> ModelRunInfo {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SunsetHueError.missingCredentials }
        var request = URLRequest(url: SunsetHueConstants.apiBaseURL.appendingPathComponent("run-info"))
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: SunsetHueConstants.apiKeyHeader)
        request.setValue(SunsetHueConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = SunsetHueConstants.apiTimeoutSeconds
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        let response = try await transport.perform(request)
        try SunsetHueClient.raiseForStatus(response)
        return try ModelRunInfoParser.parse(response.body)
    }
}

/// One shared check across locations, with short-lived results and request coalescing.
public actor ModelRunInfoMonitor {
    private let service: ModelRunInfoService
    private var cached: ModelRunInfo?
    private var validUntil: Date = .distantPast
    private var inFlight: Task<ModelRunInfo?, Never>?

    public init(service: ModelRunInfoService = ModelRunInfoService()) {
        self.service = service
    }

    public func current(apiKey: String) async -> ModelRunInfo? {
        let now = Date()
        if now < validUntil { return cached }
        if let inFlight { return await inFlight.value }

        let task = Task { [service] in try? await service.fetch(apiKey: apiKey) }
        inFlight = task
        let result = await task.value
        inFlight = nil
        cached = result

        // Never keep a cached run across its own expected publication boundary.
        // A failed check is also throttled so that many locations do not retry it.
        let ttl = now.addingTimeInterval(10 * 60)
        if let expected = result?.nextExpectedUpdate, expected > now {
            validUntil = min(ttl, expected)
        } else {
            validUntil = ttl
        }
        return result
    }
}
