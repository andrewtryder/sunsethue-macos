import Foundation

public struct ForecastDaySectionData: Equatable, Sendable, Identifiable {
    public var id: Int { dayOffset }
    public let dayOffset: Int
    public let dayLabel: String
    public let dateString: String?
    public let sunrise: EventForecast?
    public let sunset: EventForecast?

    public init(
        dayOffset: Int,
        dayLabel: String,
        dateString: String?,
        sunrise: EventForecast?,
        sunset: EventForecast?
    ) {
        self.dayOffset = dayOffset
        self.dayLabel = dayLabel
        self.dateString = dateString
        self.sunrise = sunrise
        self.sunset = sunset
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
            let sunrise = location.includeSunrise
                ? bundle.forecast(dayOffset: dayOffset, eventType: .sunrise, timeZone: timeZone)
                : nil
            let sunset = location.includeSunset
                ? bundle.forecast(dayOffset: dayOffset, eventType: .sunset, timeZone: timeZone)
                : nil
            let targetDay = cal.date(byAdding: .day, value: dayOffset, to: startOfToday)
            let dateStr = PresentationFormatting.dateLabel(targetDay, timeZone: timeZone)

            return ForecastDaySectionData(
                dayOffset: dayOffset,
                dayLabel: label,
                dateString: dateStr,
                sunrise: sunrise,
                sunset: sunset
            )
        }
    }

    public static func nextBestUpcomingEvent(
        location: SavedLocation,
        bundle: LocationForecastBundle,
        now: Date = Date()
    ) -> EventForecast? {
        let allowed = Set(location.enabledEvents)
        let futureEvents = bundle.forecasts.filter {
            allowed.contains($0.eventType) &&
            ($0.eventTime ?? Date.distantPast) > now
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
