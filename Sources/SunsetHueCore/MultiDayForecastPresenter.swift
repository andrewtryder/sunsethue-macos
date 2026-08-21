import Foundation

public enum EventDisplayState: Equatable, Sendable {
    case disabled
    case unavailable(EventType)
    case available(EventForecast)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var forecast: EventForecast? {
        if case .available(let f) = self { return f }
        return nil
    }
}

public struct ForecastDaySectionData: Equatable, Sendable, Identifiable {
    public var id: Int { dayOffset }
    public let dayOffset: Int
    public let dayLabel: String
    public let dateString: String?
    public let sunriseState: EventDisplayState
    public let sunsetState: EventDisplayState

    public var sunrise: EventForecast? { sunriseState.forecast }
    public var sunset: EventForecast? { sunsetState.forecast }

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

        return (0..<max(1, location.forecastDays)).map { dayOffset in
            let label = PresentationFormatting.relativeDayLabel(dayOffset: dayOffset, reference: now, timeZone: timeZone)

            let sunriseState: EventDisplayState
            if !location.includeSunrise {
                sunriseState = .disabled
            } else if let f = bundle.forecast(dayOffset: dayOffset, eventType: .sunrise, timeZone: timeZone, now: now) {
                sunriseState = .available(f)
            } else {
                sunriseState = .unavailable(.sunrise)
            }

            let sunsetState: EventDisplayState
            if !location.includeSunset {
                sunsetState = .disabled
            } else if let f = bundle.forecast(dayOffset: dayOffset, eventType: .sunset, timeZone: timeZone, now: now) {
                sunsetState = .available(f)
            } else {
                sunsetState = .unavailable(.sunset)
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
        let timeZone = location.timeZone ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let startOfToday = cal.startOfDay(for: now)
        guard let horizonEnd = cal.date(byAdding: .day, value: max(1, location.forecastDays), to: startOfToday) else {
            return nil
        }

        let allowed = Set(location.enabledEvents)
        let futureEvents = bundle.forecasts.filter {
            allowed.contains($0.eventType) &&
            ($0.eventTime ?? Date.distantPast) > now &&
            ($0.eventTime ?? Date.distantFuture) < horizonEnd
        }
        guard !futureEvents.isEmpty else { return nil }

        // Find the event with highest quality; if tied or no quality, pick the earliest upcoming
        return futureEvents.max { a, b in
            let qa = a.quality ?? -1.0
            let qb = b.quality ?? -1.0
            if qa != qb {
                return qa < qb
            }
            // Tie-break: earlier eventTime is better
            return (a.eventTime ?? Date.distantFuture) > (b.eventTime ?? Date.distantFuture)
        }
    }
}
