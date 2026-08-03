import Foundation
import SunsetHueCore

struct WidgetEventContent: Identifiable, Hashable {
    let id: String
    let eventType: EventType
    let dayOffset: Int
    let dayLabel: String
    let quality: Double?
    let qualityLabel: String
    let qualityText: String
    let timeLabel: String
    let goldenHourLabel: String?
    let blueHourLabel: String?
    let cloudCoverLabel: String?
    let cloudCover: Double?
    let goldenHour: MagicHourWindow?
    let blueHour: MagicHourWindow?
    let eventTime: Date?
}

struct WidgetDaySection: Identifiable, Hashable {
    var id: Int { dayOffset }
    let dayOffset: Int
    let dayLabel: String
    let timeZoneIdentifier: String
    let events: [WidgetEventContent]

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

struct WidgetResolvedContent {
    let locationName: String
    let dayLabel: String
    let primary: WidgetEventContent
    let events: [WidgetEventContent]
    let tomorrowSummary: String?
    let daySections: [WidgetDaySection]
    let accessibilityLabel: String
    /// Compact guidance when Next Events needs an extra cached forecast day.
    let hint: String?
    let isUpcoming: Bool
}

enum WidgetContentResolver {
    static func resolve(
        entry: SunsetHueEntry,
        preferSingle: Bool,
        locale: Locale = .autoupdatingCurrent
    ) -> WidgetResolvedContent? {
        guard let location = entry.location,
              let bundle = entry.bundle,
              let timeZone = location.timeZone else { return nil }

        let now = entry.date
        let selectedTypes = selectedEventTypes(for: entry, location: location)
        guard !selectedTypes.isEmpty else { return nil }

        if entry.configuration.preferredDay == .upcoming {
            return resolveUpcoming(
                location: location,
                bundle: bundle,
                timeZone: timeZone,
                selectedTypes: selectedTypes,
                preferSingle: preferSingle,
                now: now,
                locale: locale,
                eventMode: entry.configuration.eventMode
            )
        }

        return resolveFixedDay(
            entry: entry,
            location: location,
            bundle: bundle,
            timeZone: timeZone,
            selectedTypes: selectedTypes,
            preferSingle: preferSingle,
            now: now,
            locale: locale
        )
    }

    private static func resolveUpcoming(
        location: SavedLocation,
        bundle: LocationForecastBundle,
        timeZone: TimeZone,
        selectedTypes: [EventType],
        preferSingle: Bool,
        now: Date,
        locale: Locale,
        eventMode: WidgetEventMode
    ) -> WidgetResolvedContent? {
        let forecasts = UpcomingForecastSelector.forecasts(
            from: bundle,
            allowedTypes: Set(selectedTypes),
            now: now,
            limit: 4
        )
        let allEvents = forecasts.map {
            makeContent(from: $0, timeZone: timeZone, now: now, locale: locale)
        }
        guard let primary = allEvents.first else { return nil }

        let events = preferSingle ? [primary] : Array(allEvents.prefix(2))
        let sections = daySections(from: allEvents, timeZone: timeZone)
        let hint = sparseCacheHint(
            bundle: bundle,
            allowedTypes: selectedTypes,
            timeZone: timeZone,
            now: now,
            upcoming: forecasts,
            eventMode: eventMode
        )
        let accessibility = "\(location.name), Next Events, \(primary.eventType.displayName) \(primary.qualityLabel) at \(primary.timeLabel)"

        return WidgetResolvedContent(
            locationName: location.name,
            dayLabel: primary.dayLabel,
            primary: primary,
            events: events,
            tomorrowSummary: nil,
            daySections: sections,
            accessibilityLabel: accessibility,
            hint: hint,
            isUpcoming: true
        )
    }

    private static func resolveFixedDay(
        entry: SunsetHueEntry,
        location: SavedLocation,
        bundle: LocationForecastBundle,
        timeZone: TimeZone,
        selectedTypes: [EventType],
        preferSingle: Bool,
        now: Date,
        locale: Locale
    ) -> WidgetResolvedContent? {
        let dayOffset = entry.configuration.preferredDay == .tomorrow ? 1 : 0
        let dayLabel = PresentationFormatting.relativeDayLabel(
            dayOffset: dayOffset,
            reference: now,
            timeZone: timeZone
        )

        var events: [WidgetEventContent] = selectedTypes.compactMap { type in
            guard let forecast = bundle.forecast(
                dayOffset: dayOffset,
                eventType: type,
                timeZone: timeZone,
                now: now
            ) else {
                return nil
            }
            return makeContent(from: forecast, timeZone: timeZone, now: now, locale: locale)
        }

        if events.isEmpty {
            events = bundle.forecasts
                .filter { selectedTypes.contains($0.eventType) }
                .prefix(2)
                .map { makeContent(from: $0, timeZone: timeZone, now: now, locale: locale) }
        }

        guard var primary = events.first else { return nil }

        if preferSingle, selectedTypes.count > 1, events.count == 2 {
            primary = upcomingEvent(from: events, now: now) ?? primary
            events = [primary]
        }

        let tomorrow = tomorrowSummary(
            bundle: bundle,
            timeZone: timeZone,
            types: selectedTypes,
            now: now
        )
        let sections = daySections(
            bundle: bundle,
            location: location,
            timeZone: timeZone,
            types: selectedTypes,
            maxDays: min(3, location.forecastDays),
            now: now,
            locale: locale
        )
        let accessibility = "\(location.name), \(dayLabel), \(primary.eventType.displayName) \(primary.qualityLabel) at \(primary.timeLabel)"

        return WidgetResolvedContent(
            locationName: location.name,
            dayLabel: dayLabel,
            primary: primary,
            events: events,
            tomorrowSummary: tomorrow,
            daySections: sections,
            accessibilityLabel: accessibility,
            hint: nil,
            isUpcoming: false
        )
    }

    static func makeContent(
        from forecast: EventForecast,
        timeZone: TimeZone,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent
    ) -> WidgetEventContent {
        let calculator = ForecastDateCalculator()
        let dayOffset = forecast.forecastDate.flatMap {
            calculator.dayOffset(for: $0, timeZone: timeZone, now: now)
        } ?? 0
        let dayLabel = PresentationFormatting.relativeDayLabel(
            dayOffset: dayOffset,
            reference: now,
            timeZone: timeZone
        )
        let qualityLabel = PresentationFormatting.percentage(fromNormalized: forecast.quality) ?? "—"
        let time = PresentationFormatting.timeString(forecast.eventTime, timeZone: timeZone, locale: locale) ?? "—"
        let qualityText = forecast.qualityText ?? fallbackStatus(for: forecast.quality)
        let id = "\(forecast.eventType.rawValue)-\(forecast.eventTime?.timeIntervalSince1970 ?? 0)"

        return WidgetEventContent(
            id: id,
            eventType: forecast.eventType,
            dayOffset: dayOffset,
            dayLabel: dayLabel,
            quality: forecast.quality,
            qualityLabel: qualityLabel,
            qualityText: qualityText,
            timeLabel: time,
            goldenHourLabel: compactWindowLabel(prefix: "Gold", window: forecast.goldenHour, timeZone: timeZone, locale: locale),
            blueHourLabel: compactWindowLabel(prefix: "Blue", window: forecast.blueHour, timeZone: timeZone, locale: locale),
            cloudCoverLabel: PresentationFormatting.percentage(fromNormalized: forecast.cloudCover).map { "Cloud \($0)" },
            cloudCover: forecast.cloudCover,
            goldenHour: forecast.goldenHour,
            blueHour: forecast.blueHour,
            eventTime: forecast.eventTime
        )
    }

    private static func fallbackStatus(for quality: Double?) -> String {
        guard let quality else { return "Unavailable" }
        switch quality {
        case ..<0.25: return "Poor"
        case ..<0.50: return "Fair"
        case ..<0.75: return "Good"
        default: return "Excellent"
        }
    }

    private static func compactWindowLabel(
        prefix: String,
        window: MagicHourWindow?,
        timeZone: TimeZone,
        locale: Locale
    ) -> String? {
        guard let window,
              let start = PresentationFormatting.timeString(window.start, timeZone: timeZone, locale: locale),
              let end = PresentationFormatting.timeString(window.end, timeZone: timeZone, locale: locale) else {
            return nil
        }
        return "\(prefix) \(start)–\(end)"
    }

    private static func selectedEventTypes(
        for entry: SunsetHueEntry,
        location: SavedLocation
    ) -> [EventType] {
        let modeTypes: [EventType]
        switch entry.configuration.eventMode {
        case .sunrise: modeTypes = [.sunrise]
        case .sunset: modeTypes = [.sunset]
        case .both: modeTypes = [.sunrise, .sunset]
        }
        return modeTypes.filter { type in
            switch type {
            case .sunrise: return location.includeSunrise
            case .sunset: return location.includeSunset
            }
        }
    }

    private static func daySections(
        bundle: LocationForecastBundle,
        location: SavedLocation,
        timeZone: TimeZone,
        types: [EventType],
        maxDays: Int,
        now: Date,
        locale: Locale
    ) -> [WidgetDaySection] {
        (0..<maxDays).compactMap { dayOffset in
            let events = types.compactMap { type -> WidgetEventContent? in
                guard let forecast = bundle.forecast(
                    dayOffset: dayOffset,
                    eventType: type,
                    timeZone: timeZone,
                    now: now
                ) else {
                    return nil
                }
                return makeContent(from: forecast, timeZone: timeZone, now: now, locale: locale)
            }
            guard !events.isEmpty else { return nil }
            return WidgetDaySection(
                dayOffset: dayOffset,
                dayLabel: PresentationFormatting.relativeDayLabel(
                    dayOffset: dayOffset,
                    reference: now,
                    timeZone: timeZone
                ),
                timeZoneIdentifier: timeZone.identifier,
                events: events
            )
        }
    }

    private static func daySections(
        from events: [WidgetEventContent],
        timeZone: TimeZone
    ) -> [WidgetDaySection] {
        let grouped = Dictionary(grouping: events, by: \.dayOffset)
        return grouped.keys.sorted().compactMap { offset in
            guard let sectionEvents = grouped[offset],
                  let dayLabel = sectionEvents.first?.dayLabel else { return nil }
            let ordered = sectionEvents.sorted {
                ($0.eventTime ?? .distantFuture) < ($1.eventTime ?? .distantFuture)
            }
            return WidgetDaySection(
                dayOffset: offset,
                dayLabel: dayLabel,
                timeZoneIdentifier: timeZone.identifier,
                events: ordered
            )
        }
    }

    private static func upcomingEvent(from events: [WidgetEventContent], now: Date) -> WidgetEventContent? {
        let future = events
            .filter { ($0.eventTime ?? .distantPast) >= now }
            .sorted { ($0.eventTime ?? .distantFuture) < ($1.eventTime ?? .distantFuture) }
        return future.first ?? events.last
    }

    private static func tomorrowSummary(
        bundle: LocationForecastBundle,
        timeZone: TimeZone,
        types: [EventType],
        now: Date
    ) -> String? {
        let parts: [String] = types.compactMap { type in
            guard let forecast = bundle.forecast(
                dayOffset: 1,
                eventType: type,
                timeZone: timeZone,
                now: now
            ) else { return nil }
            let quality = PresentationFormatting.percentage(fromNormalized: forecast.quality) ?? "—"
            return "\(type.displayName) \(quality)"
        }
        guard !parts.isEmpty else { return nil }
        return "Tomorrow: " + parts.joined(separator: " · ")
    }

    private static func sparseCacheHint(
        bundle: LocationForecastBundle,
        allowedTypes: [EventType],
        timeZone: TimeZone,
        now: Date,
        upcoming: [EventForecast],
        eventMode: WidgetEventMode
    ) -> String? {
        let missingTomorrowTypes = allowedTypes.filter { type in
            bundle.forecast(dayOffset: 1, eventType: type, timeZone: timeZone, now: now) == nil
        }
        guard let missing = missingTomorrowTypes.first else { return nil }

        // Prefer sunrise then sunset when naming the missing type in Both mode.
        let typeName: String
        switch eventMode {
        case .sunrise:
            typeName = "sunrise"
        case .sunset:
            typeName = "sunset"
        case .both:
            if missingTomorrowTypes.contains(.sunrise) {
                typeName = "sunrise"
            } else if missingTomorrowTypes.contains(.sunset) {
                typeName = "sunset"
            } else if let last = upcoming.last {
                typeName = last.eventType == .sunrise ? "sunset" : "sunrise"
            } else {
                typeName = missing.displayName.lowercased()
            }
        }
        return "Set Forecast Days to 2 for tomorrow's \(typeName)"
    }
}
