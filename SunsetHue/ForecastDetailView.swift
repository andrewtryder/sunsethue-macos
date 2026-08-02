import SwiftUI
import SunsetHueCore

struct ForecastDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let location: SavedLocation

    private var timeZone: TimeZone {
        location.timeZone ?? .current
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let bundle = appModel.bundle, bundle.locationID == location.id {
                    ForEach(0..<location.forecastDays, id: \.self) { dayOffset in
                        DayForecastSection(
                            title: PresentationFormatting.relativeDayLabel(dayOffset: dayOffset, timeZone: timeZone),
                            sunrise: location.includeSunrise
                                ? bundle.forecast(dayOffset: dayOffset, eventType: .sunrise, timeZone: timeZone)
                                : nil,
                            sunset: location.includeSunset
                                ? bundle.forecast(dayOffset: dayOffset, eventType: .sunset, timeZone: timeZone)
                                : nil,
                            timeZone: timeZone
                        )
                    }
                    Text("Last successful update: \(bundle.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Last successful update \(bundle.fetchedAt.formatted())")
                } else if appModel.isRefreshing {
                    ProgressView("Loading forecast…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ContentUnavailableView(
                        "No Forecast Yet",
                        systemImage: "cloud.sun",
                        description: Text("Refresh to fetch sunrise and sunset quality for this location.")
                    )
                }
            }
            .padding(24)
        }
        .background(AtmosphereBackground())
        .navigationTitle(location.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { appModel.beginEditLocation(location) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(location.name)
                .font(.largeTitle.weight(.bold))
            Text("\(location.latitude), \(location.longitude) · \(location.timeZoneIdentifier)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let message = appModel.state.lastErrorMessage {
                Label(message, systemImage: appModel.state.lastErrorIsAuthentication ? "key.slash" : "wifi.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DayForecastSection: View {
    let title: String
    let sunrise: EventForecast?
    let sunset: EventForecast?
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 16) {
                if let sunrise {
                    EventForecastCard(forecast: sunrise, timeZone: timeZone)
                }
                if let sunset {
                    EventForecastCard(forecast: sunset, timeZone: timeZone)
                }
                if sunrise == nil && sunset == nil {
                    Text("No events configured for this day.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct EventForecastCard: View {
    let forecast: EventForecast
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: forecast.eventType == .sunrise ? "sunrise.fill" : "sunset.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(forecast.eventType == .sunrise ? .orange : .pink)
                    .accessibilityHidden(true)
                Text(forecast.eventType.displayName)
                    .font(.headline)
                Spacer()
                if let percent = PresentationFormatting.percentage(fromNormalized: forecast.quality) {
                    Text(percent)
                        .font(.title.weight(.bold).monospacedDigit())
                        .accessibilityLabel("Quality \(percent)")
                } else {
                    Text("Unavailable")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Quality unavailable")
                }
            }

            if let text = forecast.qualityText {
                Text(text)
                    .font(.subheadline.weight(.medium))
            }

            labeled("Event time", PresentationFormatting.timeString(forecast.eventTime, timeZone: timeZone) ?? "—")
            labeled("Cloud cover", PresentationFormatting.percentage(fromNormalized: forecast.cloudCover) ?? "—")

            HStack(spacing: 8) {
                Text("Direction")
                    .foregroundStyle(.secondary)
                Spacer()
                if let direction = forecast.direction {
                    CompassView(degrees: direction)
                        .frame(width: 28, height: 28)
                    Text(PresentationFormatting.directionLabel(direction) ?? "—")
                        .accessibilityLabel("Direction \(Int(direction)) degrees")
                } else {
                    Text("—")
                }
            }

            labeled("Golden hour", windowLabel(forecast.goldenHour))
            labeled("Blue hour", windowLabel(forecast.blueHour))
            labeled("Model data", forecast.modelData ? "Available" : "Not available")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }

    private func windowLabel(_ window: MagicHourWindow?) -> String {
        guard let window else { return "—" }
        let start = PresentationFormatting.timeString(window.start, timeZone: timeZone) ?? "—"
        let end = PresentationFormatting.timeString(window.end, timeZone: timeZone) ?? "—"
        if window.start == nil && window.end == nil { return "Unavailable" }
        return "\(start) – \(end)"
    }
}

struct CompassView: View {
    let degrees: Double

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.secondary.opacity(0.4), lineWidth: 1)
            Image(systemName: "location.north.fill")
                .resizable()
                .scaledToFit()
                .padding(6)
                .rotationEffect(.degrees(degrees))
                .accessibilityHidden(true)
        }
        .accessibilityLabel("Compass pointing \(Int(degrees)) degrees")
    }
}

struct AtmosphereBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.22, green: 0.12, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10)]
                : [Color(red: 1.0, green: 0.93, blue: 0.82), Color(red: 0.82, green: 0.90, blue: 1.0), Color(red: 0.96, green: 0.96, blue: 0.98)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview("Forecast") {
    let settings = InMemorySettingsStore(state: SharedAppState(locations: [PreviewFixtures.sampleLocation]))
    let cache = InMemoryForecastCache(store: CachedForecastStore(bundles: [
        PreviewFixtures.sampleLocationID: PreviewFixtures.sampleBundle(),
    ]))
    let model = AppModel(
        settingsStore: settings,
        forecastCache: cache,
        credentialStore: InMemoryCredentialStore(apiKey: "preview-not-a-real-key")
    )
    return ForecastDetailView(location: PreviewFixtures.sampleLocation)
        .environmentObject(model)
        .frame(width: 900, height: 700)
}
