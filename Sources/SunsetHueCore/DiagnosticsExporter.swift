import Foundation

public struct DiagnosticsExportOptions: Sendable {
    public var includeApproximateCoordinates: Bool

    public init(includeApproximateCoordinates: Bool = false) {
        self.includeApproximateCoordinates = includeApproximateCoordinates
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
        var locationEntries: [[String: Any]] = []
        for (index, location) in state.locations.enumerated() {
            let snapshot = snapshots[location.id]
            let entry: [String: Any] = [
                "display_id": "location-\(index + 1)",
                "coordinates": options.includeApproximateCoordinates
                    ? String(format: "%.1f,%.1f", location.latitude, location.longitude)
                    : "redacted",
                "time_zone": location.timeZoneIdentifier,
                "forecast_days": location.forecastDays,
                "include_sunrise": location.includeSunrise,
                "include_sunset": location.includeSunset,
                "refresh_interval_hours": location.refreshIntervalHours,
                "cache_schema_version": snapshot?.schemaVersion ?? NSNull(),
                "cache_age_seconds": snapshot.map { Int(now.timeIntervalSince($0.fetchedAt)) } as Any,
                "forecast_field_count": snapshot?.forecasts.count ?? 0,
                "status": statusString(snapshot?.status),
            ]
            locationEntries.append(entry)
            _ = apiKeyValueForRedactionTests
        }

        let processInfo = ProcessInfo.processInfo
        let report: [String: Any] = [
            "application": [
                "version": appVersion,
                "build": build,
                "architecture": architecture(),
                "macos_version": processInfo.operatingSystemVersionString,
            ],
            "sandbox": [
                "app_group_available": FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: SunsetHueConstants.appGroupIdentifier
                ) != nil,
            ],
            "credentials": [
                "configured": apiKeyConfigured,
            ],
            "locations": locationEntries,
            "widget_cache_schema_version": SunsetHueConstants.currentCacheSchemaVersion,
        ]

        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
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
