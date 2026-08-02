import Foundation
import SunsetHueCore

struct WidgetEventContent: Identifiable {
    var id: EventType { eventType }
    let eventType: EventType
    let qualityLabel: String
    let qualityText: String
    let timeLabel: String
    let magicLabel: String
    let eventTime: Date?
}

struct WidgetResolvedContent {
    let locationName: String
    let dayLabel: String
    let primary: WidgetEventContent
    let events: [WidgetEventContent]
    let tomorrowSummary: String?
    let accessibilityLabel: String
}

enum WidgetContentResolver {
    static func resolve(entry: SunsetHueEntry, preferSingle: Bool) -> WidgetResolvedContent? {
        guard let location = entry.location,
              let bundle = entry.bundle,
              let timeZone = location.timeZone else { return nil }

        let dayOffset = entry.configuration.preferredDay == .tomorrow ? 1 : 0
        let dayLabel = PresentationFormatting.relativeDayLabel(dayOffset: dayOffset, timeZone: timeZone)
        let mode = entry.configuration.eventMode

        var selectedTypes: [EventType]
        switch mode {
        case .sunrise: selectedTypes = [.sunrise]
        case .sunset: selectedTypes = [.sunset]
        case .both: selectedTypes = [.sunrise, .sunset]
        }

        var events: [WidgetEventContent] = selectedTypes.compactMap { type in
            guard let forecast = bundle.forecast(dayOffset: dayOffset, eventType: type, timeZone: timeZone) else {
                return nil
            }
            return makeContent(from: forecast, timeZone: timeZone)
        }

        if events.isEmpty {
            // Fall back to any available forecast in the bundle for the preferred types.
            events = bundle.forecasts
                .filter { selectedTypes.contains($0.eventType) }
                .prefix(2)
                .map { makeContent(from: $0, timeZone: timeZone) }
        }

        guard var primary = events.first else { return nil }

        if preferSingle, mode == .both, events.count == 2 {
            primary = upcomingEvent(from: events, now: entry.date) ?? primary
            // Keep a compact single-event presentation for small widgets.
            events = [primary]
        }

        let tomorrow = tomorrowSummary(bundle: bundle, location: location, timeZone: timeZone, mode: mode)
        let accessibility = "\(location.name), \(dayLabel), \(primary.eventType.displayName) \(primary.qualityLabel) at \(primary.timeLabel)"

        return WidgetResolvedContent(
            locationName: location.name,
            dayLabel: dayLabel,
            primary: primary,
            events: events,
            tomorrowSummary: tomorrow,
            accessibilityLabel: accessibility
        )
    }

    private static func makeContent(from forecast: EventForecast, timeZone: TimeZone) -> WidgetEventContent {
        let quality = PresentationFormatting.percentage(fromNormalized: forecast.quality) ?? "n/a"
        let time = PresentationFormatting.timeString(forecast.eventTime, timeZone: timeZone) ?? "—"
        let magic: String
        if let window = forecast.goldenHour,
           let start = PresentationFormatting.timeString(window.start, timeZone: timeZone),
           let end = PresentationFormatting.timeString(window.end, timeZone: timeZone) {
            magic = "Golden \(start)–\(end)"
        } else if let window = forecast.blueHour,
                  let start = PresentationFormatting.timeString(window.start, timeZone: timeZone),
                  let end = PresentationFormatting.timeString(window.end, timeZone: timeZone) {
            magic = "Blue \(start)–\(end)"
        } else {
            magic = forecast.modelData ? "Model ready" : "No model data"
        }
        return WidgetEventContent(
            eventType: forecast.eventType,
            qualityLabel: quality,
            qualityText: forecast.qualityText ?? (forecast.isQualityAvailable ? "Quality" : "Unavailable"),
            timeLabel: time,
            magicLabel: magic,
            eventTime: forecast.eventTime
        )
    }

    private static func upcomingEvent(from events: [WidgetEventContent], now: Date) -> WidgetEventContent? {
        let future = events
            .filter { ($0.eventTime ?? .distantPast) >= now }
            .sorted { ($0.eventTime ?? .distantFuture) < ($1.eventTime ?? .distantFuture) }
        return future.first ?? events.last
    }

    private static func tomorrowSummary(
        bundle: LocationForecastBundle,
        location: SavedLocation,
        timeZone: TimeZone,
        mode: WidgetEventMode
    ) -> String? {
        let types: [EventType]
        switch mode {
        case .sunrise: types = [.sunrise]
        case .sunset: types = [.sunset]
        case .both: types = [.sunrise, .sunset]
        }
        let parts: [String] = types.compactMap { type in
            guard let forecast = bundle.forecast(dayOffset: 1, eventType: type, timeZone: timeZone) else { return nil }
            let quality = PresentationFormatting.percentage(fromNormalized: forecast.quality) ?? "n/a"
            return "\(type.displayName) \(quality)"
        }
        guard !parts.isEmpty else { return nil }
        return "Tomorrow: " + parts.joined(separator: " · ")
    }
}
