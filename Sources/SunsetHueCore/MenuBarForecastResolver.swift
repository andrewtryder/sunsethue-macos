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
    /// Returns the event types permitted by the location's enabled events and menu-bar selection.
    public static func allowedEventTypes(
        location: SavedLocation,
        selection: MenuBarEventSelection
    ) -> Set<EventType> {
        switch selection {
        case .nextEvent:
            Set(location.enabledEvents)
        case .nextSunset:
            location.includeSunset ? [.sunset] : []
        case .nextSunrise:
            location.includeSunrise ? [.sunrise] : []
        }
    }

    /// Returns the single highest-quality usable upcoming forecast within the location's
    /// configured display horizon for `allowedTypes`.
    public static func bestUpcomingForecast(
        from bundle: LocationForecastBundle,
        location: SavedLocation,
        allowedTypes: Set<EventType>,
        now: Date
    ) -> EventForecast? {
        guard !allowedTypes.isEmpty else { return nil }
        let timeZone = location.timeZone ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: now)
        guard let horizonEnd = calendar.date(
            byAdding: .day,
            value: max(1, location.forecastDays),
            to: startOfToday
        ) else {
            return nil
        }

        return bundle.forecasts
            .compactMap { forecast -> (forecast: EventForecast, quality: Double, eventTime: Date)? in
                guard allowedTypes.contains(forecast.eventType),
                      let eventTime = forecast.eventTime,
                      eventTime > now,
                      eventTime < horizonEnd,
                      forecast.isQualityAvailable,
                      let quality = ForecastQualityTier.normalizedQuality(forecast.quality)
                else {
                    return nil
                }
                return (forecast, quality, eventTime)
            }
            .max { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality < rhs.quality
                }
                if lhs.eventTime != rhs.eventTime {
                    return lhs.eventTime > rhs.eventTime
                }
                return lhs.forecast.eventType != .sunrise && rhs.forecast.eventType == .sunrise
            }?
            .forecast
    }

    /// Returns the next matching future forecast for the location, or `nil` when none exists.
    /// Never falls back to an already-passed event.
    public static func resolve(
        location: SavedLocation,
        snapshot: CachedLocationSnapshot?,
        selection: MenuBarEventSelection,
        now: Date
    ) -> MenuBarForecastItem? {
        guard let snapshot, let bundle = snapshot.bundle else { return nil }

        let allowedTypes = allowedEventTypes(location: location, selection: selection)

        guard !allowedTypes.isEmpty,
              let forecast = UpcomingForecastSelector.forecasts(
                  from: bundle,
                  allowedTypes: allowedTypes,
                  now: now,
                  limit: 1
              ).first,
              let eventTime = forecast.eventTime
        else {
            return nil
        }

        return makeItem(from: forecast, location: location, snapshot: snapshot, eventTime: eventTime)
    }

    /// Returns the highest-quality trustworthy upcoming event within the location's configured
    /// display horizon, respecting enabled events and menu-bar event-selection preference.
    /// Returns `nil` when the snapshot is missing, stale, expired, or has no usable quality.
    public static func resolveBestUpcomingItem(
        location: SavedLocation,
        snapshot: CachedLocationSnapshot?,
        selection: MenuBarEventSelection,
        now: Date
    ) -> MenuBarForecastItem? {
        guard let snapshot,
              let bundle = snapshot.bundle,
              snapshot.status == .current,
              snapshot.isFresh(refreshIntervalHours: location.refreshIntervalHours, now: now)
        else {
            return nil
        }

        let allowedTypes = allowedEventTypes(location: location, selection: selection)
        guard let forecast = bestUpcomingForecast(
                  from: bundle,
                  location: location,
                  allowedTypes: allowedTypes,
                  now: now
              ),
              let eventTime = forecast.eventTime
        else {
            return nil
        }

        return makeItem(from: forecast, location: location, snapshot: snapshot, eventTime: eventTime)
    }

    private static func makeItem(
        from forecast: EventForecast,
        location: SavedLocation,
        snapshot: CachedLocationSnapshot,
        eventTime: Date
    ) -> MenuBarForecastItem {
        let normalizedQuality: Double? = forecast.isQualityAvailable
            ? ForecastQualityTier.normalizedQuality(forecast.quality)
            : nil
        let qualityText = MenuBarStatusFormatting.qualityTierName(
            quality: normalizedQuality,
            qualityText: forecast.qualityText
        )

        return MenuBarForecastItem(
            locationID: location.id,
            locationName: location.name,
            eventType: forecast.eventType,
            eventTime: eventTime,
            quality: normalizedQuality,
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
            !location.enabledEvents.isEmpty
        case .nextSunset:
            location.includeSunset
        case .nextSunrise:
            location.includeSunrise
        }
    }

    public static func disabledEventMessage(
        selection: MenuBarEventSelection
    ) -> String? {
        switch selection {
        case .nextEvent:
            "No sunrise or sunset events enabled for this location."
        case .nextSunset:
            "Sunset is not enabled for this location."
        case .nextSunrise:
            "Sunrise is not enabled for this location."
        }
    }
}
