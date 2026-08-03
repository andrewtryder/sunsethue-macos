import Foundation

public enum NotificationEventMode: String, Codable, CaseIterable, Sendable {
    case sunrise
    case sunset
    case both

    public var allowedTypes: Set<EventType> {
        switch self {
        case .sunrise: return [.sunrise]
        case .sunset: return [.sunset]
        case .both: return [.sunrise, .sunset]
        }
    }

    public var displayName: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .sunset: return "Sunset"
        case .both: return "Both"
        }
    }
}

public struct DailySummaryRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Minutes after local midnight for the first summary (default 08:00).
    public var firstTimeMinutes: Int
    public var secondTimeEnabled: Bool
    /// Minutes after local midnight for the optional second summary (default 16:00).
    public var secondTimeMinutes: Int

    public init(
        enabled: Bool = false,
        firstTimeMinutes: Int = 8 * 60,
        secondTimeEnabled: Bool = false,
        secondTimeMinutes: Int = 16 * 60
    ) {
        self.enabled = enabled
        self.firstTimeMinutes = firstTimeMinutes
        self.secondTimeEnabled = secondTimeEnabled
        self.secondTimeMinutes = secondTimeMinutes
    }
}

public struct QualityAlertRule: Codable, Equatable, Sendable {
    public var id: UUID
    public var enabled: Bool
    public var eventMode: NotificationEventMode
    /// Normalized 0...1 quality threshold.
    public var threshold: Double
    /// Bumped when threshold or event mode changes so prior ledger entries no longer suppress alerts.
    public var revision: Int

    public init(
        id: UUID = UUID(),
        enabled: Bool = false,
        eventMode: NotificationEventMode = .both,
        threshold: Double = 0.70,
        revision: Int = 1
    ) {
        self.id = id
        self.enabled = enabled
        self.eventMode = eventMode
        self.threshold = threshold
        self.revision = revision
    }
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var notificationsEnabled: Bool
    public var locationID: UUID?
    public var dailySummary: DailySummaryRule
    public var qualityAlert: QualityAlertRule
    public var playSound: Bool

    public init(
        schemaVersion: Int = NotificationPreferences.currentSchemaVersion,
        notificationsEnabled: Bool = false,
        locationID: UUID? = nil,
        dailySummary: DailySummaryRule = DailySummaryRule(),
        qualityAlert: QualityAlertRule = QualityAlertRule(),
        playSound: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.notificationsEnabled = notificationsEnabled
        self.locationID = locationID
        self.dailySummary = dailySummary
        self.qualityAlert = qualityAlert
        self.playSound = playSound
    }

    public var hasAnyDeliveryRuleEnabled: Bool {
        notificationsEnabled && (dailySummary.enabled || qualityAlert.enabled)
    }
}

public struct NotificationOccurrenceKey: Codable, Hashable, Sendable {
    public let ruleID: UUID
    public let revision: Int
    public let locationID: UUID
    public let eventType: EventType
    /// Local forecast calendar date `yyyy-MM-dd` in the location time zone.
    public let forecastDate: String

    public init(
        ruleID: UUID,
        revision: Int,
        locationID: UUID,
        eventType: EventType,
        forecastDate: String
    ) {
        self.ruleID = ruleID
        self.revision = revision
        self.locationID = locationID
        self.eventType = eventType
        self.forecastDate = forecastDate
    }
}

public struct NotificationLedgerEntry: Codable, Hashable, Sendable {
    public let key: NotificationOccurrenceKey
    public let recordedAt: Date

    public init(key: NotificationOccurrenceKey, recordedAt: Date = Date()) {
        self.key = key
        self.recordedAt = recordedAt
    }
}

public enum NotificationDeliveryLedgerMath {
    public static let pruneAfterDays = 7

    public static func prune(
        _ entries: [NotificationLedgerEntry],
        now: Date = Date()
    ) -> [NotificationLedgerEntry] {
        let cutoff = now.addingTimeInterval(-TimeInterval(pruneAfterDays * 86_400))
        return entries.filter { $0.recordedAt >= cutoff }
    }

    public static func contains(
        _ entries: [NotificationLedgerEntry],
        key: NotificationOccurrenceKey
    ) -> Bool {
        entries.contains { $0.key == key }
    }
}
