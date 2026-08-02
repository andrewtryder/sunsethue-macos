import WidgetKit
import SwiftUI
import SunsetHueCore

private enum WidgetPreviewData {
    static func entry(
        kind: SunsetHueEntry.Kind,
        bundle: LocationForecastBundle? = PreviewFixtures.sampleBundle(),
        status: String? = nil,
        location: SavedLocation? = PreviewFixtures.sampleLocation
    ) -> SunsetHueEntry {
        let intent = SunsetHueWidgetConfigurationIntent()
        if let location {
            intent.location = LocationEntity(location: location)
        }
        intent.eventMode = .both
        intent.preferredDay = .today
        return SunsetHueEntry(
            date: Date(),
            kind: kind,
            location: location,
            bundle: bundle,
            configuration: intent,
            statusMessage: status
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

#Preview("Medium Average", as: .systemMedium) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .forecast)
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

#Preview("Offline Cached", as: .systemSmall) {
    SunsetHueWidget()
} timeline: {
    WidgetPreviewData.entry(kind: .cached, status: "Last updated 4:12 PM")
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
