import Foundation

public struct MenuBarForecastItem: Equatable, Sendable {
    public let locationID: UUID
    public let locationName: String
    public let eventType: EventType
    public let eventTime: Date
    public let quality: Double?
    public let qualityText: String
    public let fetchedAt: Date
    public let isStale: Bool
    public let goldenHour: MagicHourWindow?
    public let blueHour: MagicHourWindow?

    public init(
        locationID: UUID,
        locationName: String,
        eventType: EventType,
        eventTime: Date,
        quality: Double?,
        qualityText: String,
        fetchedAt: Date,
        isStale: Bool,
        goldenHour: MagicHourWindow? = nil,
        blueHour: MagicHourWindow? = nil
    ) {
        self.locationID = locationID
        self.locationName = locationName
        self.eventType = eventType
        self.eventTime = eventTime
        self.quality = quality
        self.qualityText = qualityText
        self.fetchedAt = fetchedAt
        self.isStale = isStale
        self.goldenHour = goldenHour
        self.blueHour = blueHour
    }
}

public enum MenuBarForecastResolver: Sendable {
    /// Returns the next matching future forecast for the location, or `nil` when none exists.
    /// Never falls back to an already-passed event.
    public static func resolve(
        location: SavedLocation,
        snapshot: CachedLocationSnapshot?,
        selection: MenuBarEventSelection,
        now: Date
    ) -> MenuBarForecastItem? {
        guard let snapshot, let bundle = snapshot.bundle else { return nil }

        let allowedTypes: Set<EventType>
        switch selection {
        case .nextEvent:
            allowedTypes = Set(location.enabledEvents)
        case .nextSunset:
            guard location.includeSunset else { return nil }
            allowedTypes = [.sunset]
        case .nextSunrise:
            guard location.includeSunrise else { return nil }
            allowedTypes = [.sunrise]
        }

        guard !allowedTypes.isEmpty else { return nil }

        guard let forecast = UpcomingForecastSelector.forecasts(
            from: bundle,
            allowedTypes: allowedTypes,
            now: now,
            limit: 1
        ).first,
              let eventTime = forecast.eventTime else {
            return nil
        }

        let qualityText = MenuBarStatusFormatting.qualityTierName(
            quality: forecast.quality,
            qualityText: forecast.qualityText
        )

        return MenuBarForecastItem(
            locationID: location.id,
            locationName: location.name,
            eventType: forecast.eventType,
            eventTime: eventTime,
            quality: forecast.quality,
            qualityText: qualityText,
            fetchedAt: snapshot.fetchedAt,
            isStale: snapshot.status == .stale,
            goldenHour: forecast.goldenHour,
            blueHour: forecast.blueHour
        )
    }

    /// Whether the location's enabled events can satisfy the selection at all.
    public static func isSelectionEnabled(
        location: SavedLocation,
        selection: MenuBarEventSelection
    ) -> Bool {
        switch selection {
        case .nextEvent:
            return !location.enabledEvents.isEmpty
        case .nextSunset:
            return location.includeSunset
        case .nextSunrise:
            return location.includeSunrise
        }
    }

    public static func disabledEventMessage(
        selection: MenuBarEventSelection
    ) -> String? {
        switch selection {
        case .nextEvent:
            return "No sunrise or sunset events enabled for this location."
        case .nextSunset:
            return "Sunset is not enabled for this location."
        case .nextSunrise:
            return "Sunrise is not enabled for this location."
        }
    }
}
