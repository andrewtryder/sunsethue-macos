import Foundation
import Security

public enum SunsetHueConstants: Sendable {
    public static let apiBaseURL = URL(string: "https://api.sunsethue.com")!
    public static let apiEventPath = "/event"
    public static let apiKeyHeader = "x-api-key"
    public static let apiTimeoutSeconds: TimeInterval = 15
    public static let maxResponseBytes = 128 * 1024
    public static let maxRetryAfterSeconds = 24 * 60 * 60
    public static let midnightRefreshDelaySeconds = 5
    public static let fetchConcurrencyLimit = 3
    public static let minTimelineReloadSeconds = 15 * 60
    /// Pre-Sequoia iOS-style group. Kept for one-time migration only.
    public static let legacyAppGroupIdentifier = "group.com.andrewtryder.SunsetHue"
    /// macOS 15+ requires a Team-ID-prefixed App Group or widget extensions are silently denied access.
    public static var appGroupIdentifier: String {
        if let teamID = teamIdentifier, !teamID.isEmpty {
            return "\(teamID).\(legacyAppGroupIdentifier)"
        }
        return legacyAppGroupIdentifier
    }
    public static let keychainService = "com.andrewtryder.SunsetHue"
    public static let keychainAccount = "api-key"
    public static let keychainAccessGroup = "com.andrewtryder.SunsetHue.shared"
    public static let urlScheme = "sunsethue"

    /// Team ID from the code signature entitlements (empty for unsigned / ad-hoc builds).
    public static var teamIdentifier: String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.team-identifier" as CFString,
            nil
        ) as? String
    }
    /// Keep in sync with Config/Version.xcconfig and project.yml (release-please).
    public static let marketingVersion = "1.1.0" // x-release-please-version
    public static let userAgent = "SunsetHue-macOS/\(marketingVersion)"
    public static let validRefreshIntervalHours: Set<Int> = [6, 12, 24]
    public static let defaultRefreshIntervalHours = 6
    public static let defaultForecastDays = 3
    public static let maxForecastDays = 3
    public static let coordinateDecimalPlaces = 5
}

public enum EventType: String, Codable, Sendable, CaseIterable, Hashable {
    case sunrise
    case sunset

    public var displayName: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .sunset: return "Sunset"
        }
    }
}
