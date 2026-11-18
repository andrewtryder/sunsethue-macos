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
    public let bestUpcomingEventType: EventType?
    public let bestUpcomingQuality: Double?
    public let iconQualityTier: ForecastQualityTier?

    public init(
        locationName: String,
        eventType: EventType?,
        quality: Double?,
        eventTime: Date?,
        timeZone: TimeZone? = nil,
        message: String?,
        snapshotStatus: RefreshStatus? = nil,
        bestUpcomingEventType: EventType? = nil,
        bestUpcomingQuality: Double? = nil,
        iconQualityTier: ForecastQualityTier? = nil
    ) {
        self.locationName = locationName
        self.eventType = eventType
        self.quality = quality
        self.eventTime = eventTime
        self.timeZone = timeZone
        self.message = message
        self.snapshotStatus = snapshotStatus
        self.bestUpcomingEventType = bestUpcomingEventType
        self.bestUpcomingQuality = bestUpcomingQuality
        self.iconQualityTier = iconQualityTier
    }

    public var iconDescriptor: MenuBarIconDescriptor {
        MenuBarIconDescriptor(
            symbolName: symbolName,
            qualityTier: iconQualityTier,
            isTemplate: iconQualityTier == nil
        )
    }

    public static func from(
        location: SavedLocation,
        item: MenuBarForecastItem?,
        snapshot: CachedLocationSnapshot?,
        selection: MenuBarEventSelection
    ) -> MenuBarStatus {
        let trustworthyItem: MenuBarForecastItem? = if let item, !item.isStale, snapshot?.status == .current {
            item
        } else {
            nil
        }
        return from(
            location: location,
            item: item,
            snapshot: snapshot,
            selection: selection,
            bestUpcomingItem: trustworthyItem
        )
    }

    public static func from(
        location: SavedLocation,
        item: MenuBarForecastItem?,
        snapshot: CachedLocationSnapshot?,
        selection: MenuBarEventSelection,
        bestUpcomingItem: MenuBarForecastItem?
    ) -> MenuBarStatus {
        if let item {
            let bestQuality = bestUpcomingItem.flatMap { ForecastQualityTier.normalizedQuality($0.quality) }
            let bestTier = ForecastQualityTier.resolve(quality: bestQuality)
            let bestEventType = bestTier != nil ? bestUpcomingItem?.eventType : nil

            return MenuBarStatus(
                locationName: location.name,
                eventType: item.eventType,
                quality: item.quality,
                eventTime: item.eventTime,
                timeZone: location.timeZone,
                message: nil,
                snapshotStatus: snapshot?.status,
                bestUpcomingEventType: bestEventType,
                bestUpcomingQuality: bestTier != nil ? bestQuality : nil,
                iconQualityTier: bestTier
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
           let warning = MenuBarForecastResolver.disabledEventMessage(selection: selection)
        {
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
        return ForecastQualityTier.resolve(quality: quality)?.displayName ?? "Unavailable"
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

        _ = style // accessibility always includes full context
        guard let eventType = status.eventType else {
            return status.locationName
        }

        let normalizedItemQuality = ForecastQualityTier.normalizedQuality(status.quality)
        var parts = [
            status.locationName,
            "next \(eventType.displayName.lowercased())",
        ]

        if let percentage = PresentationFormatting.percentage(fromNormalized: normalizedItemQuality) {
            let qualityNumber = percentage.replacingOccurrences(of: "%", with: " percent")
            parts.append("quality \(qualityNumber)")
        } else {
            parts.append("quality unavailable")
        }

        if let timeZone = status.timeZone,
           let time = PresentationFormatting.timeString(status.eventTime, timeZone: timeZone)
        {
            parts.append("at \(time)")
        }

        if let iconTier = status.iconQualityTier {
            if let bestEvent = status.bestUpcomingEventType,
               let bestQuality = status.bestUpcomingQuality,
               let bestPercentage = PresentationFormatting.percentage(fromNormalized: bestQuality),
               bestEvent != eventType || bestQuality != normalizedItemQuality
            {
                let bestNumber = bestPercentage.replacingOccurrences(of: "%", with: " percent")
                parts.append(
                    "icon color \(iconTier.displayName.lowercased()) for best upcoming \(bestEvent.displayName.lowercased()) at \(bestNumber)"
                )
            } else {
                parts.append("icon color \(iconTier.displayName.lowercased())")
            }
        }

        return parts.joined(separator: ", ")
    }

    public static func compactWindowLabel(
        prefix: String,
        window: MagicHourWindow?,
        timeZone: TimeZone
    ) -> String? {
        guard let window,
              let start = PresentationFormatting.timeString(window.start, timeZone: timeZone),
              let end = PresentationFormatting.timeString(window.end, timeZone: timeZone)
        else {
            return nil
        }
        return "\(prefix) \(start)–\(end)"
    }

    public static func compactPercentage(fromNormalized value: Double?) -> String {
        guard let clamped = ForecastQualityTier.normalizedQuality(value) else { return "—" }
        let percent = Int((clamped * 100).rounded())
        return "\(percent)%"
    }

    public static func compactDayTimeLabel(
        eventTime: Date,
        timeZone: TimeZone,
        now: Date = Date()
    ) -> String {
        guard let timeString = PresentationFormatting.timeString(eventTime, timeZone: timeZone) else {
            return "—"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let eventDay = calendar.startOfDay(for: eventTime)
        let today = calendar.startOfDay(for: now)
        if eventDay == today {
            return timeString
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), eventDay == tomorrow {
            return "Tomorrow \(timeString)"
        }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        let dayString = formatter.string(from: eventTime)
        return "\(dayString) \(timeString)"
    }

    public static func unavailableStatus(
        location: SavedLocation,
        snapshot: CachedLocationSnapshot?,
        selection: MenuBarEventSelection
    ) -> (message: String, symbolName: String) {
        if !MenuBarForecastResolver.isSelectionEnabled(location: location, selection: selection) {
            switch selection {
            case .nextSunrise:
                return ("Sunrise disabled", "slash.circle")
            case .nextSunset:
                return ("Sunset disabled", "slash.circle")
            case .nextEvent:
                return ("No events enabled", "slash.circle")
            }
        }
        guard let snapshot else {
            return ("No forecast available", "minus.circle")
        }
        switch snapshot.status {
        case .authenticationRequired:
            return ("API key needed", "key.slash")
        case .rateLimited:
            return ("Rate limited", "clock.badge.exclamationmark")
        case .temporarilyUnavailable:
            return ("Temporarily unavailable", "exclamationmark.triangle")
        case .invalidRequest:
            return ("Invalid location", "exclamationmark.triangle")
        case .invalidResponse:
            return ("Incompatible response", "exclamationmark.triangle")
        case .stale:
            return ("Forecast stale", "arrow.clockwise")
        case .current:
            return ("No forecast available", "minus.circle")
        }
    }
}

public enum MenuBarAppearanceVariant: String, Hashable, Sendable {
    case light
    case dark
}

public struct MenuBarIconCacheKey: Hashable, Sendable {
    public let symbolName: String
    public let qualityTier: ForecastQualityTier?
    public let appearance: MenuBarAppearanceVariant
    public let isHighContrast: Bool

    public init(
        symbolName: String,
        qualityTier: ForecastQualityTier?,
        appearance: MenuBarAppearanceVariant,
        isHighContrast: Bool
    ) {
        self.symbolName = symbolName
        self.qualityTier = qualityTier
        self.appearance = appearance
        self.isHighContrast = isHighContrast
    }
}

public struct MenuBarIconDescriptor: Equatable, Sendable {
    public let symbolName: String
    public let qualityTier: ForecastQualityTier?
    public let isTemplate: Bool

    public init(symbolName: String, qualityTier: ForecastQualityTier?, isTemplate: Bool) {
        self.symbolName = symbolName
        self.qualityTier = qualityTier
        self.isTemplate = isTemplate
    }

    public func cacheKey(
        appearance: MenuBarAppearanceVariant,
        isHighContrast: Bool
    ) -> MenuBarIconCacheKey {
        MenuBarIconCacheKey(
            symbolName: symbolName,
            qualityTier: qualityTier,
            appearance: appearance,
            isHighContrast: isHighContrast
        )
    }
}

public struct MenuBarLabelContent: Equatable, Sendable {
    public let symbolName: String
    public let title: String
    public let accessibilityLabel: String
    public let iconQualityTier: ForecastQualityTier?
    public let iconDescriptor: MenuBarIconDescriptor

    public init(
        symbolName: String,
        title: String,
        accessibilityLabel: String,
        iconQualityTier: ForecastQualityTier? = nil
    ) {
        self.symbolName = symbolName
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.iconQualityTier = iconQualityTier
        iconDescriptor = MenuBarIconDescriptor(
            symbolName: symbolName,
            qualityTier: iconQualityTier,
            isTemplate: iconQualityTier == nil
        )
    }

    public static func resolve(
        locations: [SavedLocation],
        snapshots: [UUID: CachedLocationSnapshot],
        preferences: MenuBarPreferences,
        selectedLocationID: UUID?,
        now: Date = Date(),
        epoch: Date = Date(timeIntervalSince1970: 0)
    ) -> MenuBarLabelContent {
        guard let location = MenuBarRotationLogic.locationForLabel(
            locations: locations,
            snapshots: snapshots,
            preferences: preferences,
            selectedLocationID: selectedLocationID,
            now: now,
            epoch: epoch
        ) else {
            return MenuBarLabelContent(
                symbolName: "sun.horizon",
                title: preferences.displayStyle == .iconOnly ? "" : "SunsetHue",
                accessibilityLabel: "SunsetHue",
                iconQualityTier: nil
            )
        }

        let snapshot = snapshots[location.id]
        let item = MenuBarForecastResolver.resolve(
            location: location,
            snapshot: snapshot,
            selection: preferences.eventSelection,
            now: now
        )
        let bestUpcomingItem = MenuBarForecastResolver.resolveBestUpcomingItem(
            location: location,
            snapshot: snapshot,
            selection: preferences.eventSelection,
            now: now
        )
        let status = MenuBarStatus.from(
            location: location,
            item: item,
            snapshot: snapshot,
            selection: preferences.eventSelection,
            bestUpcomingItem: bestUpcomingItem
        )
        return MenuBarLabelContent(
            symbolName: status.symbolName,
            title: MenuBarStatusFormatting.labelText(for: status, style: preferences.displayStyle),
            accessibilityLabel: MenuBarStatusFormatting.accessibilityLabel(
                for: status,
                style: preferences.displayStyle
            ),
            iconQualityTier: status.iconQualityTier
        )
    }
}
