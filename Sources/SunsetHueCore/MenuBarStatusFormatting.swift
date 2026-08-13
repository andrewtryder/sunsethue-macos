import Foundation

/// Compact status for the menu-bar extra label.
public struct MenuBarStatus: Equatable, Sendable {
    public let locationName: String
    public let eventType: EventType?
    public let quality: Double?
    public let eventTime: Date?
    public let timeZone: TimeZone?
    /// Short label fallback (e.g. "API key needed"). Nil when the location name should show instead.
    public let message: String?
    public let snapshotStatus: RefreshStatus?

    public init(
        locationName: String,
        eventType: EventType?,
        quality: Double?,
        eventTime: Date?,
        timeZone: TimeZone? = nil,
        message: String?,
        snapshotStatus: RefreshStatus? = nil
    ) {
        self.locationName = locationName
        self.eventType = eventType
        self.quality = quality
        self.eventTime = eventTime
        self.timeZone = timeZone
        self.message = message
        self.snapshotStatus = snapshotStatus
    }

    public static func from(
        location: SavedLocation,
        item: MenuBarForecastItem?,
        snapshot: CachedLocationSnapshot?,
        selection: MenuBarEventSelection
    ) -> MenuBarStatus {
        if let item {
            return MenuBarStatus(
                locationName: location.name,
                eventType: item.eventType,
                quality: item.quality,
                eventTime: item.eventTime,
                timeZone: location.timeZone,
                message: nil,
                snapshotStatus: snapshot?.status
            )
        }

        if let snapshot {
            switch snapshot.status {
            case .authenticationRequired:
                return MenuBarStatus(
                    locationName: location.name,
                    eventType: nil,
                    quality: nil,
                    eventTime: nil,
                    timeZone: location.timeZone,
                    message: "API key needed",
                    snapshotStatus: snapshot.status
                )
            case .rateLimited:
                return MenuBarStatus(
                    locationName: location.name,
                    eventType: nil,
                    quality: nil,
                    eventTime: nil,
                    timeZone: location.timeZone,
                    message: "Rate limited",
                    snapshotStatus: snapshot.status
                )
            case .temporarilyUnavailable:
                return MenuBarStatus(
                    locationName: location.name,
                    eventType: nil,
                    quality: nil,
                    eventTime: nil,
                    timeZone: location.timeZone,
                    message: "Unavailable",
                    snapshotStatus: snapshot.status
                )
            default:
                break
            }
        }

        if !MenuBarForecastResolver.isSelectionEnabled(location: location, selection: selection),
           let warning = MenuBarForecastResolver.disabledEventMessage(selection: selection) {
            return MenuBarStatus(
                locationName: location.name,
                eventType: nil,
                quality: nil,
                eventTime: nil,
                timeZone: location.timeZone,
                message: warning,
                snapshotStatus: snapshot?.status
            )
        }

        return MenuBarStatus(
            locationName: location.name,
            eventType: nil,
            quality: nil,
            eventTime: nil,
            timeZone: location.timeZone,
            message: nil,
            snapshotStatus: snapshot?.status
        )
    }

    public var symbolName: String {
        if let eventType {
            switch eventType {
            case .sunrise: return "sunrise.fill"
            case .sunset: return "sunset.fill"
            }
        }
        switch snapshotStatus {
        case .authenticationRequired:
            return "key.slash"
        case .rateLimited:
            return "clock.badge.exclamationmark"
        case .temporarilyUnavailable, .invalidRequest, .invalidResponse:
            return "exclamationmark.triangle"
        default:
            if message != nil {
                return "exclamationmark.triangle"
            }
            return "sun.horizon"
        }
    }
}

public enum MenuBarStatusFormatting: Sendable {
    public static let maxLocationNameLength = 18

    /// Fallback quality tier when the API omits `quality_text`.
    public static func qualityTierName(quality: Double?, qualityText: String? = nil) -> String {
        if let qualityText, !qualityText.isEmpty {
            return qualityText
        }
        guard let quality else { return "Unavailable" }
        switch quality {
        case ..<0.25: return "Poor"
        case ..<0.50: return "Fair"
        case ..<0.75: return "Good"
        default: return "Excellent"
        }
    }

    public static func truncatedLocationName(_ name: String, maxLength: Int = maxLocationNameLength) -> String {
        guard name.count > maxLength else { return name }
        let end = name.index(name.startIndex, offsetBy: max(1, maxLength - 1))
        return String(name[..<end]) + "…"
    }

    public static func labelText(
        for status: MenuBarStatus,
        style: MenuBarDisplayStyle
    ) -> String {
        if let message = status.message {
            return message
        }

        let location = truncatedLocationName(status.locationName)

        guard
            let eventType = status.eventType,
            let percentage = PresentationFormatting.percentage(fromNormalized: status.quality)
        else {
            return location
        }

        let timeZone = status.timeZone ?? .current
        let time = PresentationFormatting.timeString(status.eventTime, timeZone: timeZone)

        switch style {
        case .iconOnly:
            return ""
        case .eventQuality:
            return "\(eventType.displayName) \(percentage)"
        case .locationEventQuality:
            return "\(location) · \(eventType.displayName) \(percentage)"
        case .locationEventQualityTime:
            if let time {
                return "\(location) · \(eventType.displayName) \(percentage) · \(time)"
            }
            return "\(location) · \(eventType.displayName) \(percentage)"
        }
    }

    public static func accessibilityLabel(
        for status: MenuBarStatus,
        style: MenuBarDisplayStyle = .locationEventQuality
    ) -> String {
        if let message = status.message {
            return "\(status.locationName), \(message)"
        }

        guard
            let eventType = status.eventType,
            let percentage = PresentationFormatting.percentage(fromNormalized: status.quality)
        else {
            return status.locationName
        }

        let qualityNumber = percentage.replacingOccurrences(of: "%", with: " percent")
        var parts = [
            status.locationName,
            "next \(eventType.displayName.lowercased())",
            "quality \(qualityNumber)",
        ]
        if let timeZone = status.timeZone,
           let time = PresentationFormatting.timeString(status.eventTime, timeZone: timeZone) {
            parts.append("at \(time)")
        }
        _ = style // accessibility always includes full context
        return parts.joined(separator: ", ")
    }

    public static func compactWindowLabel(
        prefix: String,
        window: MagicHourWindow?,
        timeZone: TimeZone
    ) -> String? {
        guard let window,
              let start = PresentationFormatting.timeString(window.start, timeZone: timeZone),
              let end = PresentationFormatting.timeString(window.end, timeZone: timeZone) else {
            return nil
        }
        return "\(prefix) \(start)–\(end)"
    }

    public static func relativeEventDayLabel(
        eventTime: Date,
        timeZone: TimeZone,
        now: Date = Date()
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let eventDay = calendar.startOfDay(for: eventTime)
        let today = calendar.startOfDay(for: now)
        if eventDay == today {
            return "Today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), eventDay == tomorrow {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: eventTime)
    }
}
