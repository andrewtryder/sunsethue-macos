import Foundation

public enum EventDisplayState: Equatable, Sendable {
    case disabled
    case unavailable(EventType)
    case available(EventForecast)

    public var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    public var forecast: EventForecast? {
        if case let .available(f) = self {
            return f
        }
        return nil
    }
}

public struct ForecastDaySectionData: Equatable, Sendable, Identifiable {
    public var id: Int {
        dayOffset
    }

    public let dayOffset: Int
    public let dayLabel: String
    public let dateString: String?
    public let sunriseState: EventDisplayState
    public let sunsetState: EventDisplayState

    public var sunrise: EventForecast? {
        sunriseState.forecast
    }

    public var sunset: EventForecast? {
        sunsetState.forecast
    }

    public init(
        dayOffset: Int,
        dayLabel: String,
        dateString: String?,
        sunriseState: EventDisplayState,
        sunsetState: EventDisplayState
    ) {
        self.dayOffset = dayOffset
        self.dayLabel = dayLabel
        self.dateString = dateString
        self.sunriseState = sunriseState
        self.sunsetState = sunsetState
    }
}

public enum MultiDayForecastPresenter: Sendable {
    public static func buildSections(
        location: SavedLocation,
        bundle: LocationForecastBundle,
        now: Date = Date()
    ) -> [ForecastDaySectionData] {
        let timeZone = location.timeZone ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let startOfToday = cal.startOfDay(for: now)

        return (0 ..< max(1, location.forecastDays)).map { dayOffset in
            let label = PresentationFormatting.relativeDayLabel(dayOffset: dayOffset, reference: now, timeZone: timeZone)

            let sunriseState: EventDisplayState = if !location.includeSunrise {
                .disabled
            } else if let f = bundle.forecast(dayOffset: dayOffset, eventType: .sunrise, timeZone: timeZone, now: now) {
                .available(f)
            } else {
                .unavailable(.sunrise)
            }

            let sunsetState: EventDisplayState = if !location.includeSunset {
                .disabled
            } else if let f = bundle.forecast(dayOffset: dayOffset, eventType: .sunset, timeZone: timeZone, now: now) {
                .available(f)
            } else {
                .unavailable(.sunset)
            }

            let targetDay = cal.date(byAdding: .day, value: dayOffset, to: startOfToday)
            let dateStr = PresentationFormatting.dateLabel(targetDay, timeZone: timeZone)

            return ForecastDaySectionData(
                dayOffset: dayOffset,
                dayLabel: label,
                dateString: dateStr,
                sunriseState: sunriseState,
                sunsetState: sunsetState
            )
        }
    }

    public static func nextBestUpcomingEvent(
        location: SavedLocation,
        bundle: LocationForecastBundle,
        now: Date = Date()
    ) -> EventForecast? {
        MenuBarForecastResolver.bestUpcomingForecast(
            from: bundle,
            location: location,
            allowedTypes: Set(location.enabledEvents),
            now: now
        )
    }
}
