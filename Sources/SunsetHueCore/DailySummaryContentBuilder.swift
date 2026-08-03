import Foundation

public struct NotificationContentDraft: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum DailySummaryContentBuilder: Sendable {
    /// Builds summary copy from upcoming forecasts relative to `deliveryDate`.
    public static func content(
        location: SavedLocation,
        bundle: LocationForecastBundle,
        deliveryDate: Date,
        locale: Locale = .autoupdatingCurrent
    ) -> NotificationContentDraft? {
        guard let timeZone = location.timeZone else { return nil }
        let upcoming = UpcomingForecastSelector.forecasts(
            from: bundle,
            allowedTypes: Set(location.enabledEvents),
            now: deliveryDate,
            limit: 2
        )
        guard let first = upcoming.first else { return nil }

        let hour = localHour(deliveryDate, timeZone: timeZone)
        if hour >= 12, first.eventType == .sunset {
            return afternoonSunsetSummary(
                locationName: location.name,
                forecast: first,
                timeZone: timeZone,
                locale: locale
            )
        }

        return multiEventSummary(
            locationName: location.name,
            forecasts: upcoming,
            deliveryDate: deliveryDate,
            timeZone: timeZone,
            locale: locale
        )
    }

    private static func multiEventSummary(
        locationName: String,
        forecasts: [EventForecast],
        deliveryDate: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> NotificationContentDraft {
        let parts = forecasts.map {
            forecastPhrase(
                $0,
                deliveryDate: deliveryDate,
                timeZone: timeZone,
                locale: locale,
                includeTomorrowPrefix: true
            )
        }
        return NotificationContentDraft(
            title: "\(locationName) forecast",
            body: parts.joined(separator: " · ")
        )
    }

    private static func afternoonSunsetSummary(
        locationName: String,
        forecast: EventForecast,
        timeZone: TimeZone,
        locale: Locale
    ) -> NotificationContentDraft {
        let quality = PresentationFormatting.percentage(fromNormalized: forecast.quality) ?? "—"
        let time = PresentationFormatting.timeString(forecast.eventTime, timeZone: timeZone, locale: locale) ?? "—"
        var body = "Sunset at \(time)"
        if let gold = compactWindow(forecast.goldenHour, timeZone: timeZone, locale: locale) {
            body += " · Gold \(gold)"
        }
        return NotificationContentDraft(
            title: "\(locationName) sunset forecast: \(quality)",
            body: body
        )
    }

    private static func forecastPhrase(
        _ forecast: EventForecast,
        deliveryDate: Date,
        timeZone: TimeZone,
        locale: Locale,
        includeTomorrowPrefix: Bool
    ) -> String {
        let quality = PresentationFormatting.percentage(fromNormalized: forecast.quality) ?? "—"
        let status = forecast.qualityText ?? fallbackStatus(forecast.quality)
        let time = PresentationFormatting.timeString(forecast.eventTime, timeZone: timeZone, locale: locale) ?? "—"
        var name = forecast.eventType.displayName
        if includeTomorrowPrefix,
           let forecastDate = forecast.forecastDate,
           let offset = ForecastDateCalculator().dayOffset(
            for: forecastDate,
            timeZone: timeZone,
            now: deliveryDate
           ),
           offset == 1 {
            name = "Tomorrow \(forecast.eventType.displayName.lowercased())"
        }
        return "\(name) \(quality) \(status) at \(time)"
    }

    private static func compactWindow(
        _ window: MagicHourWindow?,
        timeZone: TimeZone,
        locale: Locale
    ) -> String? {
        guard let window,
              let start = PresentationFormatting.timeString(window.start, timeZone: timeZone, locale: locale),
              let end = PresentationFormatting.timeString(window.end, timeZone: timeZone, locale: locale) else {
            return nil
        }
        return "\(start)–\(end)"
    }

    private static func fallbackStatus(_ quality: Double?) -> String {
        guard let quality else { return "Unavailable" }
        switch quality {
        case ..<0.25: return "Poor"
        case ..<0.50: return "Fair"
        case ..<0.75: return "Good"
        default: return "Excellent"
        }
    }

    private static func localHour(_ date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}
