import Foundation

/// Public preview/sample data. Uses well-known public coordinates only. Never includes API keys.
public enum PreviewFixtures {
    public static let sampleLocationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    public static let sampleTimeZone = TimeZone(identifier: "America/New_York")!

    /// Public NYC City Hall vicinity (rounded) — not a private address.
    public static let sampleCoordinates = Coordinates(latitude: 40.71280, longitude: -74.00600)

    public static var sampleLocation: SavedLocation {
        SavedLocation(
            id: sampleLocationID,
            name: "Sample Harbor",
            latitude: sampleCoordinates.latitude,
            longitude: sampleCoordinates.longitude,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 3,
            includeSunrise: true,
            includeSunset: true,
            refreshIntervalHours: 6
        )
    }

    public static func excellentSunset(on day: Date = Date()) -> EventForecast {
        makeForecast(
            eventType: .sunset,
            modelData: true,
            quality: 0.92,
            qualityText: "Excellent",
            cloudCover: 0.12,
            direction: 278,
            day: day,
            hourUTC: 23,
            minute: 15
        )
    }

    public static func averageSunrise(on day: Date = Date()) -> EventForecast {
        makeForecast(
            eventType: .sunrise,
            modelData: true,
            quality: 0.48,
            qualityText: "Average",
            cloudCover: 0.41,
            direction: 62,
            day: day,
            hourUTC: 10,
            minute: 5
        )
    }

    public static func missingModelQuality(on day: Date = Date()) -> EventForecast {
        EventForecast(
            responseTime: Date(),
            location: sampleCoordinates,
            gridLocation: Coordinates(latitude: 41.0, longitude: -74.0),
            eventType: .sunset,
            modelData: false,
            quality: nil,
            qualityText: nil,
            cloudCover: nil,
            eventTime: eventDate(day: day, hourUTC: 23, minute: 11),
            direction: 256.7,
            blueHour: MagicHourWindow(start: nil, end: nil),
            goldenHour: nil,
            forecastDate: Calendar(identifier: .gregorian).startOfDay(for: day)
        )
    }

    public static var longNameLocation: SavedLocation {
        SavedLocation(
            id: sampleLocationID,
            name: "Sandown Harbor North Scenic Overlook, NH",
            latitude: sampleCoordinates.latitude,
            longitude: sampleCoordinates.longitude,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 3,
            includeSunrise: true,
            includeSunset: true,
            refreshIntervalHours: 6
        )
    }

    /// Quality-band edge cases (normalized 0...1).
    public static func qualityBandForecast(
        quality: Double?,
        qualityText: String? = nil,
        eventType: EventType = .sunset,
        on day: Date = Date(),
        hourUTC: Int = 23,
        minute: Int = 6
    ) -> EventForecast {
        makeForecast(
            eventType: eventType,
            modelData: quality != nil,
            quality: quality,
            qualityText: qualityText,
            cloudCover: quality.map { min(1, max(0, 1 - $0)) } ?? 1,
            direction: eventType == .sunset ? 278 : 62,
            day: day,
            hourUTC: hourUTC,
            minute: minute
        )
    }

    public static func perfectSunset(on day: Date = Date()) -> EventForecast {
        makeForecast(
            eventType: .sunset,
            modelData: true,
            quality: 1.0,
            qualityText: "Excellent",
            cloudCover: 0.05,
            direction: 278,
            day: day,
            hourUTC: 23,
            minute: 10
        )
    }

    public static func threeDayCompleteBundle(fetchedAt: Date = Date()) -> LocationForecastBundle {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sampleTimeZone
        let today = calendar.startOfDay(for: fetchedAt)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: today)!
        return LocationForecastBundle(
            locationID: sampleLocationID,
            fetchedAt: fetchedAt,
            forecasts: [
                averageSunrise(on: today),
                excellentSunset(on: today),
                qualityBandForecast(quality: 0.0, qualityText: "Poor", eventType: .sunrise, on: tomorrow, hourUTC: 10, minute: 6)
                    .withForecastDate(tomorrow),
                qualityBandForecast(quality: 0.36, qualityText: "Fair", eventType: .sunset, on: tomorrow, hourUTC: 23, minute: 5)
                    .withForecastDate(tomorrow),
                qualityBandForecast(quality: 0.18, eventType: .sunrise, on: dayAfter, hourUTC: 10, minute: 7)
                    .withForecastDate(dayAfter),
                qualityBandForecast(quality: 0.62, qualityText: "Good", eventType: .sunset, on: dayAfter, hourUTC: 23, minute: 4)
                    .withForecastDate(dayAfter),
            ]
        )
    }

    public static func sampleBundle(fetchedAt: Date = Date()) -> LocationForecastBundle {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sampleTimeZone
        let today = calendar.startOfDay(for: fetchedAt)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: today)!
        return LocationForecastBundle(
            locationID: sampleLocationID,
            fetchedAt: fetchedAt,
            forecasts: [
                averageSunrise(on: today),
                excellentSunset(on: today),
                averageSunrise(on: tomorrow).withForecastDate(tomorrow),
                excellentSunset(on: tomorrow).withForecastDate(tomorrow),
                missingModelQuality(on: dayAfter).withForecastDate(dayAfter),
            ]
        )
    }

    private static func makeForecast(
        eventType: EventType,
        modelData: Bool,
        quality: Double?,
        qualityText: String?,
        cloudCover: Double?,
        direction: Double?,
        day: Date,
        hourUTC: Int,
        minute: Int
    ) -> EventForecast {
        let eventTime = eventDate(day: day, hourUTC: hourUTC, minute: minute)
        let goldenStart = eventTime.addingTimeInterval(eventType == .sunset ? -27 * 60 : 0)
        let goldenEnd = eventTime.addingTimeInterval(eventType == .sunset ? 5 * 60 : 27 * 60)
        let blueStart = eventTime.addingTimeInterval(eventType == .sunset ? 13 * 60 : -20 * 60)
        let blueEnd = eventTime.addingTimeInterval(eventType == .sunset ? 26 * 60 : -5 * 60)
        return EventForecast(
            responseTime: Date(),
            location: sampleCoordinates,
            gridLocation: Coordinates(latitude: 41.0, longitude: -74.0),
            eventType: eventType,
            modelData: modelData,
            quality: quality,
            qualityText: qualityText,
            cloudCover: cloudCover,
            eventTime: eventTime,
            direction: direction,
            blueHour: MagicHourWindow(start: blueStart, end: blueEnd),
            goldenHour: MagicHourWindow(start: goldenStart, end: goldenEnd),
            forecastDate: Calendar(identifier: .gregorian).startOfDay(for: day)
        )
    }

    private static func eventDate(day: Date, hourUTC: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hourUTC
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? day
    }
}
