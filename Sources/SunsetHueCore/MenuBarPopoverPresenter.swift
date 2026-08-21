import Foundation

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
    public let isStale: Bool
    public let isRefreshing: Bool
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
        isStale: Bool = false,
        isRefreshing: Bool = false,
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
        self.isStale = isStale
        self.isRefreshing = isRefreshing
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
        isRefreshing: Bool = false,
        now: Date = Date()
    ) -> MenuBarPopoverRow {
        let timeZone = location.timeZone ?? .current
        let item = MenuBarForecastResolver.resolve(
            location: location,
            snapshot: snapshot,
            selection: preferences.eventSelection,
            now: now
        )

        let isStale = (snapshot?.status == .stale) || (snapshot != nil && !snapshot!.isFresh(refreshIntervalHours: location.refreshIntervalHours, now: now))

        if let item {
            let dayTime = MenuBarStatusFormatting.compactDayTimeLabel(
                eventTime: item.eventTime,
                timeZone: timeZone,
                now: now
            )
            let quality = MenuBarStatusFormatting.compactPercentage(fromNormalized: item.quality)
            let qualityNumber = quality.replacingOccurrences(of: "%", with: " percent")
            let staleSuffix = isStale ? ", forecast is stale" : ""
            let accessibility = "\(item.eventType.displayName), \(dayTime), quality \(qualityNumber)\(staleSuffix)"
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
                isStale: isStale,
                isRefreshing: isRefreshing,
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
            isStale: isStale,
            isRefreshing: isRefreshing,
            accessibilityValue: message
        )
    }

    public static func buildRows(
        locations: [SavedLocation],
        snapshots: [UUID: CachedLocationSnapshot],
        preferences: MenuBarPreferences,
        selectedLocationID: UUID?,
        refreshingLocationIDs: Set<UUID> = [],
        now: Date = Date()
    ) -> [MenuBarPopoverRow] {
        let effectiveSelectedID = selectedLocationID ?? locations.first?.id
        return locations.map { location in
            row(
                for: location,
                snapshot: snapshots[location.id],
                preferences: preferences,
                isSelected: location.id == effectiveSelectedID,
                isRefreshing: refreshingLocationIDs.contains(location.id),
                now: now
            )
        }
    }
}
