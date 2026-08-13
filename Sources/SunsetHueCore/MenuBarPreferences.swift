import Foundation

public struct MenuBarPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let storageKey = "menuBarPreferences.v1"
    public static let legacyDisplayStyleKey = "menuBarDisplayStyle"

    public var schemaVersion: Int
    public var displayStyle: MenuBarDisplayStyle
    public var eventSelection: MenuBarEventSelection
    public var locationMode: MenuBarLocationMode
    public var rotationIntervalSeconds: Int

    public static let allowedRotationIntervals = [5, 10, 15, 30]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        displayStyle: MenuBarDisplayStyle = .locationEventQuality,
        eventSelection: MenuBarEventSelection = .nextEvent,
        locationMode: MenuBarLocationMode = .selectedLocation,
        rotationIntervalSeconds: Int = 10
    ) {
        self.schemaVersion = schemaVersion
        self.displayStyle = displayStyle
        self.eventSelection = eventSelection
        self.locationMode = locationMode
        self.rotationIntervalSeconds = Self.clampRotationInterval(rotationIntervalSeconds)
    }

    public static func clampRotationInterval(_ value: Int) -> Int {
        if allowedRotationIntervals.contains(value) { return value }
        return 10
    }

    /// Migrate from a legacy single-key display style string, if present.
    public static func migratedDisplayStyle(fromLegacyRaw raw: String?) -> MenuBarDisplayStyle? {
        guard let raw else { return nil }
        switch raw {
        case "iconOnly":
            return .iconOnly
        case "eventAndQuality", "eventQuality":
            return .eventQuality
        case "locationEventAndQuality", "locationEventQuality":
            return .locationEventQuality
        case "locationEventQualityTime":
            return .locationEventQualityTime
        default:
            return MenuBarDisplayStyle(rawValue: raw)
        }
    }
}

public enum MenuBarDisplayStyle: String, Codable, CaseIterable, Sendable {
    case iconOnly
    case eventQuality
    case locationEventQuality
    case locationEventQualityTime

    public var settingsLabel: String {
        switch self {
        case .iconOnly:
            return "Icon only"
        case .eventQuality:
            return "Event and quality"
        case .locationEventQuality:
            return "Location, event, and quality"
        case .locationEventQualityTime:
            return "Location, event, quality, and time"
        }
    }
}

public enum MenuBarEventSelection: String, Codable, CaseIterable, Sendable {
    case nextEvent
    case nextSunset
    case nextSunrise

    public var settingsLabel: String {
        switch self {
        case .nextEvent:
            return "Next sunrise or sunset"
        case .nextSunset:
            return "Next sunset"
        case .nextSunrise:
            return "Next sunrise"
        }
    }

    public var requiredEventType: EventType? {
        switch self {
        case .nextEvent: return nil
        case .nextSunset: return .sunset
        case .nextSunrise: return .sunrise
        }
    }
}

public enum MenuBarLocationMode: String, Codable, CaseIterable, Sendable {
    case selectedLocation
    case rotateLocations

    public var settingsLabel: String {
        switch self {
        case .selectedLocation:
            return "Selected location"
        case .rotateLocations:
            return "Rotate through all configured locations"
        }
    }
}
