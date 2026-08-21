import Foundation
import Security

public enum SunsetHueConstants: Sendable {
    public static let apiBaseURL = URL(string: "https://api.sunsethue.com")!
    public static let apiEventPath = "/event"
    public static let apiKeyHeader = "x-api-key"
    public static let apiTimeoutSeconds: TimeInterval = 15
    public static let maxResponseBytes = 128 * 1024
    public static let maxSettingsFileBytes = 256 * 1024
    public static let maxCacheFileBytes = 512 * 1024
    public static let maxRetryAfterSeconds = 24 * 60 * 60
    public static let midnightRefreshDelaySeconds = 5
    public static let fetchConcurrencyLimit = 3
    public static let minTimelineReloadSeconds = 15 * 60
    public static let maxTimelineJitterSeconds = 15 * 60
    public static let currentSettingsSchemaVersion = 1
    public static let currentCacheSchemaVersion = 3
    public static let widgetKind = "SunsetHueWidget"
    /// Temporary-unavailable backoff ladder (seconds), capped at `maxRefreshBackoffSeconds`.
    public static let temporaryUnavailableBackoffSeconds: [TimeInterval] = [
        15 * 60, 30 * 60, 60 * 60, 2 * 60 * 60,
    ]
    public static let invalidResponseInitialBackoffSeconds: TimeInterval = 60 * 60
    public static let maxRefreshBackoffSeconds: TimeInterval = 6 * 60 * 60
    public static let rateLimitJitterMaxSeconds = 60
    /// Base App Group name. On macOS 15+, App Groups must be prefixed with the signing Team ID.
    public static let baseAppGroupIdentifier = "group.com.andrewtryder.SunsetHue"

    /// Formats the Team-ID-prefixed App Group identifier.
    public static func teamAppGroupIdentifier(teamID: String) -> String {
        "\(teamID).\(baseAppGroupIdentifier)"
    }

    /// Historical raw identifier; NEVER accessed during normal runtime.
    @available(*, deprecated, message: "Raw group.com.andrewtryder.SunsetHue triggers privacy prompts and is never queried.")
    public static let legacyAppGroupIdentifier = "group.com.andrewtryder.SunsetHue"

    /// macOS 15+ requires a Team-ID-prefixed App Group or widget extensions are silently denied access.
    /// Returns nil when no Team ID exists (e.g. unsigned / ad-hoc builds).
    public static var appGroupIdentifier: String? {
        guard let teamID = teamIdentifier, !teamID.isEmpty else {
            return nil
        }
        return teamAppGroupIdentifier(teamID: teamID)
    }
    public static let keychainService = "com.andrewtryder.SunsetHue"
    /// App-only Keychain account (not shared with the widget).
    public static let keychainAccount = "api-key-v2"
    public static let urlScheme = "sunsethue"
    public static let githubReleasesLatestURL = URL(
        string: "https://api.github.com/repos/andrewtryder/sunsethue-macos/releases/latest"
    )!
    public static let githubReleasesPageURL = URL(
        string: "https://github.com/andrewtryder/sunsethue-macos/releases/latest"
    )!

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
    public static let marketingVersion = "1.2.0" // x-release-please-version
    public static let userAgent = "SunsetHue-macOS/\(marketingVersion)"
    public static let validRefreshIntervalHours: Set<Int> = [6, 12, 24]
    public static let defaultRefreshIntervalHours = 6
    public static let defaultForecastDays = 1
    public static let minimumOperationalForecastDays = 2
    public static let maxForecastDays = 3
    public static let coordinateDecimalPlaces = 5

    /// Deterministic 0..<maxTimelineJitterSeconds derived from a location UUID (FNV-1a).
    /// Stable across process launches (unlike Swift.Hasher).
    public static func timelineJitterSeconds(for locationID: UUID) -> Int {
        Int(fnv1a32(uuid: locationID) % UInt32(maxTimelineJitterSeconds))
    }

    /// Deterministic 0..<rateLimitJitterMaxSeconds for rate-limit retry scheduling.
    public static func rateLimitJitterSeconds(for locationID: UUID) -> Int {
        Int(fnv1a32(uuid: locationID) % UInt32(rateLimitJitterMaxSeconds))
    }

    private static func fnv1a32(uuid: UUID) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        withUnsafeBytes(of: uuid.uuid) { buffer in
            for byte in buffer {
                hash ^= UInt32(byte)
                hash &*= 16_777_619
            }
        }
        return hash
    }
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

    public var symbolName: String {
        switch self {
        case .sunrise: return "sunrise.fill"
        case .sunset: return "sunset.fill"
        }
    }
}

