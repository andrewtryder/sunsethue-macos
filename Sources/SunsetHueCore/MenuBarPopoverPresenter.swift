import Foundation

/// Presentation model for a single compact row in the menu-bar window dropdown.
public struct MenuBarPopoverRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let eventType: EventType?
    public let eventLabel: String?
    public let dayTimeLabel: String?
    public let qualityLabel: String?
    public let statusMessage: String?
    public let statusSymbolName: String?
    public let isSelected: Bool
    public let accessibilityValue: String

    public init(
        id: UUID,
        name: String,
        eventType: EventType? = nil,
        eventLabel: String? = nil,
        dayTimeLabel: String? = nil,
        qualityLabel: String? = nil,
        statusMessage: String? = nil,
        statusSymbolName: String? = nil,
        isSelected: Bool = false,
        accessibilityValue: String = ""
    ) {
        self.id = id
        self.name = name
        self.eventType = eventType
        self.eventLabel = eventLabel
        self.dayTimeLabel = dayTimeLabel
        self.qualityLabel = qualityLabel
        self.statusMessage = statusMessage
        self.statusSymbolName = statusSymbolName
        self.isSelected = isSelected
        self.accessibilityValue = accessibilityValue
    }
}

/// Pure presenter that transforms configured locations into compact dropdown rows.
public enum MenuBarPopoverPresenter: Sendable {
    public static func row(
        for location: SavedLocation,
        snapshot: CachedLocationSnapshot?,
        preferences: MenuBarPreferences,
        isSelected: Bool,
        now: Date = Date()
    ) -> MenuBarPopoverRow {
        let timeZone = location.timeZone ?? .current
        let item = MenuBarForecastResolver.resolve(
            location: location,
            snapshot: snapshot,
            selection: preferences.eventSelection,
            now: now
        )

        if let item {
            let dayTime = MenuBarStatusFormatting.compactDayTimeLabel(
                eventTime: item.eventTime,
                timeZone: timeZone,
                now: now
            )
            let quality = MenuBarStatusFormatting.compactPercentage(fromNormalized: item.quality)
            let qualityNumber = quality.replacingOccurrences(of: "%", with: " percent")
            let accessibility = "\(item.eventType.displayName), \(dayTime), quality \(qualityNumber)"
            return MenuBarPopoverRow(
                id: location.id,
                name: location.name,
                eventType: item.eventType,
                eventLabel: item.eventType.displayName,
                dayTimeLabel: dayTime,
                qualityLabel: quality,
                statusMessage: nil,
                statusSymbolName: nil,
                isSelected: isSelected,
                accessibilityValue: accessibility
            )
        }

        let (message, symbol) = MenuBarStatusFormatting.unavailableStatus(
            location: location,
            snapshot: snapshot,
            selection: preferences.eventSelection
        )
        return MenuBarPopoverRow(
            id: location.id,
            name: location.name,
            eventType: nil,
            eventLabel: nil,
            dayTimeLabel: nil,
            qualityLabel: nil,
            statusMessage: message,
            statusSymbolName: symbol,
            isSelected: isSelected,
            accessibilityValue: message
        )
    }

    public static func buildRows(
        locations: [SavedLocation],
        snapshots: [UUID: CachedLocationSnapshot],
        preferences: MenuBarPreferences,
        selectedLocationID: UUID?,
        now: Date = Date()
    ) -> [MenuBarPopoverRow] {
        let effectiveSelectedID = selectedLocationID ?? locations.first?.id
        return locations.map { location in
            row(
                for: location,
                snapshot: snapshots[location.id],
                preferences: preferences,
                isSelected: location.id == effectiveSelectedID,
                now: now
            )
        }
    }
}
