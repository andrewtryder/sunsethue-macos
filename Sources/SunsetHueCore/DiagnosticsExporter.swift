import Foundation

public struct DiagnosticsExportOptions: Sendable {
    public var includeApproximateCoordinates: Bool

    public init(includeApproximateCoordinates: Bool = false) {
        self.includeApproximateCoordinates = includeApproximateCoordinates
    }
}

public struct DiagnosticsReport: Codable, Equatable, Sendable {
    public struct Application: Codable, Equatable, Sendable {
        public var version: String
        public var build: String
        public var architecture: String
        public var macosVersion: String

        enum CodingKeys: String, CodingKey {
            case version, build, architecture
            case macosVersion = "macos_version"
        }
    }

    public struct Sandbox: Codable, Equatable, Sendable {
        public var appGroupAvailable: Bool

        enum CodingKeys: String, CodingKey {
            case appGroupAvailable = "app_group_available"
        }
    }

    public struct Credentials: Codable, Equatable, Sendable {
        public var configured: Bool
    }

    public struct LocationEntry: Codable, Equatable, Sendable {
        public var displayID: String
        public var coordinates: String
        public var timeZone: String
        public var forecastDays: Int
        public var includeSunrise: Bool
        public var includeSunset: Bool
        public var refreshIntervalHours: Int
        public var cacheSchemaVersion: Int?
        public var cacheAgeSeconds: Int?
        public var forecastFieldCount: Int
        public var status: String

        enum CodingKeys: String, CodingKey {
            case displayID = "display_id"
            case coordinates
            case timeZone = "time_zone"
            case forecastDays = "forecast_days"
            case includeSunrise = "include_sunrise"
            case includeSunset = "include_sunset"
            case refreshIntervalHours = "refresh_interval_hours"
            case cacheSchemaVersion = "cache_schema_version"
            case cacheAgeSeconds = "cache_age_seconds"
            case forecastFieldCount = "forecast_field_count"
            case status
        }
    }

    public var application: Application
    public var sandbox: Sandbox
    public var credentials: Credentials
    public var locations: [LocationEntry]
    public var widgetCacheSchemaVersion: Int
    public var notes: [String]

    enum CodingKeys: String, CodingKey {
        case application, sandbox, credentials, locations, notes
        case widgetCacheSchemaVersion = "widget_cache_schema_version"
    }
}

public struct DiagnosticsExporter: Sendable {
    public init() {}

    public func makeReport(
        state: SharedAppState,
        snapshots: [UUID: CachedLocationSnapshot],
        apiKeyConfigured: Bool,
        apiKeyValueForRedactionTests: String? = nil,
        options: DiagnosticsExportOptions = DiagnosticsExportOptions(),
        appVersion: String = SunsetHueConstants.marketingVersion,
        build: String = "1",
        now: Date = Date()
    ) throws -> Data {
        let locationEntries: [DiagnosticsReport.LocationEntry] = state.locations.enumerated().map { index, location in
            let snapshot = snapshots[location.id]
            let age = snapshot.map { max(0, Int(now.timeIntervalSince($0.fetchedAt))) }
            return DiagnosticsReport.LocationEntry(
                displayID: "location-\(index + 1)",
                coordinates: options.includeApproximateCoordinates
                    ? String(format: "%.1f,%.1f", location.latitude, location.longitude)
                    : "redacted",
                timeZone: location.timeZoneIdentifier,
                forecastDays: location.forecastDays,
                includeSunrise: location.includeSunrise,
                includeSunset: location.includeSunset,
                refreshIntervalHours: location.refreshIntervalHours,
                cacheSchemaVersion: snapshot?.schemaVersion,
                cacheAgeSeconds: age,
                forecastFieldCount: snapshot?.forecasts.count ?? 0,
                status: statusString(snapshot?.status)
            )
        }

        let processInfo = ProcessInfo.processInfo
        var notes = [
            "Diagnostic exports never include the API key.",
        ]
        if !options.includeApproximateCoordinates {
            notes.append(
                "Time zone identifiers can imply a broad geographic region even when coordinates are redacted."
            )
        }

        let report = DiagnosticsReport(
            application: .init(
                version: appVersion,
                build: build,
                architecture: architecture(),
                macosVersion: processInfo.operatingSystemVersionString
            ),
            sandbox: .init(
                appGroupAvailable: FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: SunsetHueConstants.appGroupIdentifier
                ) != nil
            ),
            credentials: .init(configured: apiKeyConfigured),
            locations: locationEntries,
            widgetCacheSchemaVersion: SunsetHueConstants.currentCacheSchemaVersion,
            notes: notes
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        if let secret = apiKeyValueForRedactionTests, !secret.isEmpty {
            if let text = String(data: data, encoding: .utf8), text.contains(secret) {
                throw SunsetHueError.invalidResponse("diagnostics_leaked_secret")
            }
        }
        return data
    }

    private func statusString(_ status: RefreshStatus?) -> String {
        guard let status else { return "missing" }
        switch status {
        case .current: return "current"
        case .stale: return "stale"
        case .authenticationRequired: return "authentication_required"
        case .rateLimited: return "rate_limited"
        case .temporarilyUnavailable: return "temporarily_unavailable"
        case .invalidRequest: return "invalid_request"
        case .invalidResponse: return "invalid_response"
        }
    }

    private func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
