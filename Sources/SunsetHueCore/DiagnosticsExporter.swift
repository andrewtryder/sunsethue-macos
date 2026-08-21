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

    public struct Notifications: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var dailySummaryEnabled: Bool
        public var secondDailySummaryEnabled: Bool
        public var firstTimeMinutes: Int
        public var secondTimeMinutes: Int
        public var qualityAlertEnabled: Bool
        public var qualityThreshold: Double
        public var qualityEventMode: String
        public var hasLocationConfigured: Bool

        enum CodingKeys: String, CodingKey {
            case enabled
            case dailySummaryEnabled = "daily_summary_enabled"
            case secondDailySummaryEnabled = "second_daily_summary_enabled"
            case firstTimeMinutes = "first_time_minutes"
            case secondTimeMinutes = "second_time_minutes"
            case qualityAlertEnabled = "quality_alert_enabled"
            case qualityThreshold = "quality_threshold"
            case qualityEventMode = "quality_event_mode"
            case hasLocationConfigured = "has_location_configured"
        }
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
    public var notifications: Notifications?
    public var locations: [LocationEntry]
    public var widgetCacheSchemaVersion: Int
    public var notes: [String]

    enum CodingKeys: String, CodingKey {
        case application, sandbox, credentials, notifications, locations, notes
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
        now: Date = Date(),
        notificationPreferences: NotificationPreferences? = nil
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

        let notificationsSummary = notificationPreferences.map { prefs in
            DiagnosticsReport.Notifications(
                enabled: prefs.notificationsEnabled,
                dailySummaryEnabled: prefs.dailySummary.enabled,
                secondDailySummaryEnabled: prefs.dailySummary.secondTimeEnabled,
                firstTimeMinutes: prefs.dailySummary.firstTimeMinutes,
                secondTimeMinutes: prefs.dailySummary.secondTimeMinutes,
                qualityAlertEnabled: prefs.qualityAlert.enabled,
                qualityThreshold: prefs.qualityAlert.threshold,
                qualityEventMode: prefs.qualityAlert.eventMode.rawValue,
                hasLocationConfigured: prefs.locationID != nil
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
                appGroupAvailable: {
                    if case .teamAppGroup(let id) = AppSupportPaths.currentStorageMode() {
                        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil
                    }
                    return false
                }()
            ),
            credentials: .init(configured: apiKeyConfigured),
            notifications: notificationsSummary,
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

    public func makePlainTextDiagnostics(
        state: SharedAppState,
        snapshots: [UUID: CachedLocationSnapshot],
        storageDiagnostics: StorageDiagnostics,
        backgroundDiagnostics: BackgroundRefreshDiagnostics,
        recentActivity: [RefreshActivityRecord],
        notificationPreferences: NotificationPreferences?,
        notificationAuthorization: String,
        apiKeyConfigured: Bool,
        apiKeyValueForRedactionTests: String? = nil,
        appVersion: String = SunsetHueConstants.marketingVersion,
        build: String = "1",
        now: Date = Date(),
        options: DiagnosticsExportOptions = DiagnosticsExportOptions()
    ) throws -> String {
        var lines: [String] = []
        lines.append("SunsetHue Diagnostics")
        lines.append("====================")
        lines.append("App Version: \(appVersion) (\(build))")
        lines.append("macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Architecture: \(architecture())")
        lines.append("Storage Mode: \(storageDiagnostics.storageModeDisplayName)")
        if let groupID = storageDiagnostics.appGroupIdentifier {
            lines.append("App Group Identifier: \(groupID)")
            lines.append("App Group Available: \(storageDiagnostics.isAppGroupAvailable ? "Yes" : "No")")
        } else {
            lines.append("App Group: Not configured (Unsigned / Local fallback)")
        }
        lines.append("Shared Settings File: \(storageDiagnostics.isSettingsReadable ? "Readable" : "Unavailable")")
        lines.append("Shared Forecast Cache: \(storageDiagnostics.isForecastCacheReadable ? "Readable" : "Unavailable")")
        if let commit = storageDiagnostics.lastCacheCommit {
            lines.append("Last Cache Commit: \(PresentationFormatting.iso8601String(from: commit))")
        } else {
            lines.append("Last Cache Commit: None")
        }
        lines.append("Widget Sharing: \(storageDiagnostics.isAppGroupAvailable ? "Available" : "Local only")")
        if let reload = storageDiagnostics.lastWidgetReloadRequested {
            lines.append("Last Widget Reload Requested: \(PresentationFormatting.iso8601String(from: reload))")
        } else {
            lines.append("Last Widget Reload Requested: None")
        }
        lines.append("API Key: \(apiKeyConfigured ? "Configured" : "Not configured")")
        lines.append("")
        lines.append("Background Refresh:")
        lines.append("  Status: \(backgroundDiagnostics.isActive ? "Active" : "Inactive")")
        lines.append("  Scheduler: \(backgroundDiagnostics.schedulerName)")
        lines.append("  Interval: \(backgroundDiagnostics.intervalDescription) (Timing controlled by macOS energy management)")
        if let act = backgroundDiagnostics.lastActivityAt {
            lines.append("  Last Activity: \(PresentationFormatting.iso8601String(from: act))")
        } else {
            lines.append("  Last Activity: None")
        }
        lines.append("  Last Disposition: \(backgroundDiagnostics.lastDisposition ?? "None")")
        lines.append("  Launch at Login: \(backgroundDiagnostics.isLaunchAtLoginEnabled ? "On" : "Off")")
        lines.append("")
        // Build location anonymization map
        var locationLabels: [UUID: String] = [:]
        for (index, location) in state.locations.enumerated() {
            locationLabels[location.id] = "Location \(index + 1)"
        }

        lines.append("Notifications:")
        lines.append("  Authorization: \(notificationAuthorization)")
        if let notif = notificationPreferences {
            lines.append("  Master Enabled: \(notif.notificationsEnabled ? "Yes" : "No")")
            lines.append("  Play Sound: \(notif.playSound ? "Yes" : "No")")
            if state.locations.isEmpty {
                lines.append("  Location Rules: None")
            } else {
                for (index, location) in state.locations.enumerated() {
                    let label = "Location \(index + 1)"
                    let rule = notif.rule(for: location.id)
                    let qualityDesc = rule.qualityAlert.enabled
                        ? "Alerts >= \(Int(rule.qualityAlert.threshold * 100))% (\(rule.qualityAlert.eventMode.displayName))"
                        : "Alerts off"
                    let summaryDesc = rule.dailySummary.enabled
                        ? "Summary \(rule.dailySummary.firstTimeMinutes / 60):\(String(format: "%02d", rule.dailySummary.firstTimeMinutes % 60))"
                        : "Summary off"
                    lines.append("  - \(label): \(qualityDesc), \(summaryDesc)")
                }
            }
        } else {
            lines.append("  Preferences: Not configured")
        }
        lines.append("")
        lines.append("Locations (\(state.locations.count)):")
        for (index, location) in state.locations.enumerated() {
            let snap = snapshots[location.id]
            let diag = LocationRefreshDiagnostics.make(location: location, snapshot: snap, isRefreshing: false, now: now)
            let coords = options.includeApproximateCoordinates
                ? String(format: " (%.1f, %.1f)", location.latitude, location.longitude)
                : ""
            let anonymizedTitle = "Location \(index + 1)"
            lines.append("  - \(anonymizedTitle)\(coords):")
            lines.append("      Status: \(diag.statusDisplayName)")
            if let succ = diag.lastSuccess {
                lines.append("      Last Success: \(PresentationFormatting.iso8601String(from: succ))")
            } else {
                lines.append("      Last Success: None")
            }
            if let att = diag.lastAttempt {
                lines.append("      Last Attempt: \(PresentationFormatting.iso8601String(from: att))")
            } else {
                lines.append("      Last Attempt: None")
            }
            if let next = diag.nextScheduledRefresh {
                lines.append("      Next Scheduled: \(PresentationFormatting.iso8601String(from: next))")
            } else {
                lines.append("      Next Scheduled: None")
            }
            lines.append("      Cache Coverage: \(diag.coverageDescription)")
            lines.append("      Refresh Interval: \(diag.refreshIntervalHours) hours")
        }
        lines.append("")
        lines.append("Recent Activity (Newest First):")
        if recentActivity.isEmpty {
            lines.append("  (No recent refresh activity recorded)")
        } else {
            for entry in recentActivity {
                let time = PresentationFormatting.iso8601String(from: entry.timestamp)
                let label = entry.locationID.flatMap { locationLabels[$0] } ?? "Location"
                let detailStr: String
                if let details = entry.details {
                    let sanitized = details.replacingOccurrences(of: #"/Users/[^/\s]+(/[^/\s]+)*"#, with: "[path]", options: .regularExpression)
                    detailStr = " - \(sanitized)"
                } else {
                    detailStr = ""
                }
                lines.append("  - [\(time)] \(label): \(entry.trigger.rawValue) -> \(entry.result.rawValue)\(detailStr)")
            }
        }

        let output = lines.joined(separator: "\n")
        if let secret = apiKeyValueForRedactionTests, !secret.isEmpty {
            if output.contains(secret) {
                throw SunsetHueError.invalidResponse("diagnostics_leaked_secret")
            }
        }
        return output
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
