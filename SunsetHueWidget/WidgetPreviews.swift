import WidgetKit
import SwiftUI
import SunsetHueCore

private enum WidgetPreviewData {
    static func entry(
        kind: SunsetHueEntry.Kind,
        bundle: LocationForecastBundle? = PreviewFixtures.sampleBundle(),
        status: String? = nil,
        location: SavedLocation? = PreviewFixtures.sampleLocation,
        date: Date = Date(),
        preferredDay: WidgetPreferredDay = .today,
        eventMode: WidgetEventMode = .both
    ) -> SunsetHueEntry {
        let intent = SunsetHueWidgetConfigurationIntent()
        if let location {
            intent.location = LocationEntity(location: location)
        }
        intent.eventMode = eventMode
        intent.preferredDay = preferredDay
        return SunsetHueEntry(
            date: date,
            kind: kind,
            location: location,
            bundle: bundle,
            configuration: intent,
            statusMessage: status
        )
    }

    /// After today's sample sunrise (10:05 UTC), before sunset — Next Events should show sunset then tomorrow sunrise.
    static var afterSunriseDate: Date {
        let sunrise = PreviewFixtures.averageSunrise()
        return (sunrise.eventTime ?? Date()).addingTimeInterval(60 * 60)
    }

    /// After today's sample sunset — Next Events should advance to tomorrow.
    static var afterSunsetDate: Date {
        let sunset = PreviewFixtures.excellentSunset()
        return (sunset.eventTime ?? Date()).addingTimeInterval(60 * 60)
    }

    static var oneDayLocation: SavedLocation {
        SavedLocation(
            id: PreviewFixtures.sampleLocationID,
            name: PreviewFixtures.sampleLocation.name,
            latitude: PreviewFixtures.sampleCoordinates.latitude,
            longitude: PreviewFixtures.sampleCoordinates.longitude,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 1,
            includeSunrise: true,
            includeSunset: true,
            refreshIntervalHours: 6
        )
    }

    static func todayOnlyBundle(fetchedAt: Date = Date()) -> LocationForecastBundle {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PreviewFixtures.sampleTimeZone
        let today = calendar.startOfDay(for: fetchedAt)
        return LocationForecastBundle(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: fetchedAt,
            forecasts: [
                PreviewFixtures.averageSunrise(on: today),
                PreviewFixtures.excellentSunset(on: today),
            ]
        )
    }

    static func bandBundle(quality: Double?, qualityText: String? = nil) -> LocationForecastBundle {
        LocationForecastBundle(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: Date(),
            forecasts: [
                PreviewFixtures.qualityBandForecast(
                    quality: quality,
                    qualityText: qualityText,
                    eventType: .sunset
                )
            ]
        )
    }
}

#Preview("Small Excellent", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast, bundle: LocationForecastBundle(
        locationID: PreviewFixtures.sampleLocationID,
        fetchedAt: Date(),
        forecasts: [PreviewFixtures.excellentSunset(), PreviewFixtures.averageSunrise()]
    ))
}

#Preview("Small 100%", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: LocationForecastBundle(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: Date(),
            forecasts: [PreviewFixtures.perfectSunset()]
        )
    )
}

#Preview("Small Missing Quality", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: LocationForecastBundle(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: Date(),
            forecasts: [PreviewFixtures.missingModelQuality()]
        )
    )
}

#Preview("Medium Both Magic Hours", as: .systemMedium) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast)
}

#Preview("Large Cloud Gold Blue Line", as: .systemLarge) {
    SunsetHueWidget()
} timeline: {
    // Cloud symbol + whole-number % with Gold/Blue windows on one metadata line.
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: PreviewFixtures.threeDayCompleteBundle(),
        status: WidgetUpdatedCopy.compactUpdated(from: Date().addingTimeInterval(-20 * 60))
    )
}

#Preview("Small Next Events After Sunset", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: PreviewFixtures.sampleBundle(),
        date: WidgetPreviewData.afterSunsetDate,
        preferredDay: .upcoming
    )
}

#Preview("Medium Next Events After Sunrise", as: .systemMedium) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: PreviewFixtures.sampleBundle(),
        date: WidgetPreviewData.afterSunriseDate,
        preferredDay: .upcoming
    )
}

#Preview("Large Next Events", as: .systemLarge) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: PreviewFixtures.threeDayCompleteBundle(),
        date: WidgetPreviewData.afterSunriseDate,
        preferredDay: .upcoming
    )
}

#Preview("Medium Next Events Sparse Cache", as: .systemMedium) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: WidgetPreviewData.todayOnlyBundle(),
        location: WidgetPreviewData.oneDayLocation,
        date: WidgetPreviewData.afterSunriseDate,
        preferredDay: .upcoming
    )
}

#Preview("Large Long Location Name", as: .systemLarge) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: PreviewFixtures.threeDayCompleteBundle(),
        location: PreviewFixtures.longNameLocation
    )
}

#Preview("Large Missing Model", as: .systemLarge) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: LocationForecastBundle(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: Date(),
            forecasts: [
                PreviewFixtures.averageSunrise(),
                PreviewFixtures.missingModelQuality(),
            ]
        )
    )
}

#Preview("Quality 0%", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast, bundle: WidgetPreviewData.bandBundle(quality: 0.0))
}

#Preview("Quality 24.9%", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast, bundle: WidgetPreviewData.bandBundle(quality: 0.249))
}

#Preview("Quality 25%", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast, bundle: WidgetPreviewData.bandBundle(quality: 0.25))
}

#Preview("Quality 49.9%", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast, bundle: WidgetPreviewData.bandBundle(quality: 0.499))
}

#Preview("Quality 50%", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast, bundle: WidgetPreviewData.bandBundle(quality: 0.50))
}

#Preview("Quality 74.9%", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast, bundle: WidgetPreviewData.bandBundle(quality: 0.749))
}

#Preview("Quality 75%", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast, bundle: WidgetPreviewData.bandBundle(quality: 0.75))
}

#Preview("Quality 100%", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast, bundle: WidgetPreviewData.bandBundle(quality: 1.0, qualityText: "Excellent"))
}

#Preview("Twelve Hour Clock") {
    // Force en_US so AM/PM labels appear even when the Mac uses 24-hour time.
    // Widget `#Preview(as:)` cannot inject locale into DateFormatter-backed labels.
    let entry = WidgetPreviewData.entry(kind: .forecast, bundle: PreviewFixtures.sampleBundle())
    TwelveHourClockPreviewHost(entry: entry)
        .containerBackground(for: .widget) { WidgetAtmosphereBackground() }
        .frame(width: 360, height: 169)
}

/// Host that re-resolves content with a fixed 12-hour locale for preview coverage.
private struct TwelveHourClockPreviewHost: View {
    let entry: SunsetHueEntry
    private let twelveHourLocale = Locale(identifier: "en_US")

    var body: some View {
        if let content = WidgetContentResolver.resolve(entry: entry, preferSingle: false, locale: twelveHourLocale) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(
                    locationName: content.locationName,
                    updatedText: WidgetUpdatedCopy.text(for: entry)
                )
                HStack(alignment: .top, spacing: 12) {
                    if content.events.count >= 1 {
                        MediumEventColumn(event: content.events[0])
                    }
                    if content.events.count >= 2 {
                        Divider()
                        MediumEventColumn(event: content.events[1])
                    }
                }
                if let tomorrow = content.tomorrowSummary {
                    Text(tomorrow)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            OnboardingWidgetView(message: "No data")
        }
    }
}

#Preview("Quality Badge Contrast Sample", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    // Note: Widget `#Preview(as:)` cannot set colorSchemeContrast / differentiateWithoutColor
    // (those EnvironmentValues key paths are read-only). Badge + status text remain the non-color signal.
    WidgetPreviewData.entry(
        kind: .forecast,
        bundle: WidgetPreviewData.bandBundle(quality: 0.82, qualityText: "Excellent")
    )
}

#Preview("Quality Band Text Fallback", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    // No API qualityText — badge falls back to band label ("Poor") as non-color signal.
    WidgetPreviewData.entry(kind: .forecast, bundle: WidgetPreviewData.bandBundle(quality: 0.18))
}

#Preview("Stale Compact", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(
        kind: .stale,
        bundle: PreviewFixtures.sampleBundle(fetchedAt: Date().addingTimeInterval(-9 * 3600)),
        status: "Updated 9h ago"
    )
}

#Preview("Offline Cached", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .cached, status: "Updated 4:12 PM")
}

#Preview("Auth Error", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .authentication, status: "Open SunsetHue to update API key.")
}

#Preview("No Location", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .onboarding, bundle: nil, status: "Open SunsetHue to add a location.", location: nil)
}
