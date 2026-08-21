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
                    if let bestEvent = MultiDayForecastPresenter.nextBestUpcomingEvent(location: location, bundle: bundle) {
                        UpcomingOpportunityBanner(forecast: bestEvent, timeZone: timeZone)
                    }

                    let sections = MultiDayForecastPresenter.buildSections(location: location, bundle: bundle)
                    ForEach(sections) { section in
                        DayForecastSection(section: section, timeZone: timeZone)
                    }

                    Text("Last successful update: \(bundle.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .sunsetHueMuted()
                        .accessibilityLabel("Last successful update")
                        .accessibilityValue(bundle.fetchedAt.formatted())
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
                Button {
                    Task { await appModel.refreshSelected(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appModel.isRefreshing)
            }
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
            if let message = appModel.lastErrorMessage {
                Label(message, systemImage: appModel.lastErrorIsAuthentication ? "key.slash" : "wifi.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            AtmospherePanelBackground()
        }
    }
}

struct UpcomingOpportunityBanner: View {
    let forecast: EventForecast
    let timeZone: TimeZone

    private var qualityStyle: QualityStyle {
        QualityStyle.resolve(quality: forecast.quality, qualityText: forecast.qualityText)
    }

    var body: some View {
        SectionCard {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(qualityStyle.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Top Upcoming Opportunity")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(qualityStyle.tint)
                        .textCase(.uppercase)

                    HStack(spacing: 6) {
                        Image(systemName: forecast.eventType.symbolName)
                            .foregroundStyle(forecast.eventType.iconColor)
                        Text(forecast.eventType.displayName)
                            .font(.headline)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(PresentationFormatting.timeString(forecast.eventTime, timeZone: timeZone) ?? "—")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Text(qualityStyle.percentage)
                        .font(SunsetHueTypography.cardTitle.weight(.bold))
                        .foregroundStyle(qualityStyle.tint)

                    StatusBadge(quality: qualityStyle)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Top Upcoming Opportunity: \(forecast.eventType.displayName), \(qualityStyle.percentage), \(qualityStyle.status)")
    }
}

struct DayForecastSection: View {
    let section: ForecastDaySectionData
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.dayLabel)
                    .font(SunsetHueTypography.sectionHeader)
                    .accessibilityAddTraits(.isHeader)

                if let dateStr = section.dateString, section.dayOffset < 2 {
                    Text(dateStr)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                if let sunrise = section.sunrise {
                    EventForecastCard(forecast: sunrise, timeZone: timeZone)
                }
                if let sunset = section.sunset {
                    EventForecastCard(forecast: sunset, timeZone: timeZone)
                }
                if section.sunrise == nil && section.sunset == nil {
                    Text("No events configured for this day.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct EventForecastCard: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let forecast: EventForecast
    let timeZone: TimeZone

    private var qualityStyle: QualityStyle {
        QualityStyle.resolve(quality: forecast.quality, qualityText: forecast.qualityText)
    }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: forecast.eventType.symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(forecast.eventType.iconColor)
                        .accessibilityHidden(true)
                    Text(forecast.eventType.displayName)
                        .font(SunsetHueTypography.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    if differentiateWithoutColor {
                        Text(forecast.eventType == .sunrise ? "AM" : "PM")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 8)
                    Text(PresentationFormatting.timeString(forecast.eventTime, timeZone: timeZone) ?? "—")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .center, spacing: 12) {
                    Text(qualityStyle.percentage)
                        .font(SunsetHueTypography.heroQuality)
                        .foregroundStyle(qualityStyle.tint)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel("Forecast quality")
                        .accessibilityValue("\(qualityStyle.percentage), \(qualityStyle.status)")

                    StatusBadge(quality: qualityStyle)
                        .accessibilityHidden(true)

                    Spacer(minLength: 0)

                    QualityAccentBar(tint: qualityStyle.tint)
                        .frame(width: 6, height: 44)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    labeled("Cloud cover", PresentationFormatting.percentage(fromNormalized: forecast.cloudCover) ?? "—")
                    directionRow
                    windowRow("Golden hour", forecast.goldenHour)
                    windowRow("Blue hour", forecast.blueHour)
                }
                .padding(.top, 2)

                Text("Model data: \(forecast.modelData ? "Available" : "Not available")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Model data")
                    .accessibilityValue(forecast.modelData ? "Available" : "Not available")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(forecast.eventType.displayName) forecast")
    }

    private var directionRow: some View {
        HStack(spacing: 8) {
            Text("Direction")
                .foregroundStyle(.secondary)
            Spacer()
            if let direction = forecast.direction {
                CompassView(degrees: direction)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text(PresentationFormatting.directionLabel(direction) ?? "—")
                    .accessibilityLabel("Direction")
                    .accessibilityValue("\(Int(direction)) degrees")
            } else {
                Text("—")
                    .accessibilityLabel("Direction")
                    .accessibilityValue("Unavailable")
            }
        }
        .font(.callout)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func windowRow(_ title: String, _ window: MagicHourWindow?) -> some View {
        let value = windowLabel(window)
        return HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func windowLabel(_ window: MagicHourWindow?) -> String {
        guard let window else { return "—" }
        let start = PresentationFormatting.timeString(window.start, timeZone: timeZone) ?? "—"
        let end = PresentationFormatting.timeString(window.end, timeZone: timeZone) ?? "—"
        if window.start == nil && window.end == nil { return "Unavailable" }
        return "\(start) – \(end)"
    }
}

private struct QualityAccentBar: View {
    let tint: Color

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.85))
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
        }
        .accessibilityHidden(true)
    }
}

struct AtmospherePanelBackground: View {
    var body: some View {
        SharedPanelBackground()
    }
}

struct AtmosphereBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if reduceTransparency {
                Rectangle().fill(solidColor)
            } else {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay {
            if contrast == .increased {
                Rectangle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 2)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: colorScheme)
        .ignoresSafeArea()
    }

    private var solidColor: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.10, blue: 0.18)
            : Color(red: 0.96, green: 0.96, blue: 0.98)
    }

    private var gradientColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.22, green: 0.12, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10)]
            : [Color(red: 1.0, green: 0.93, blue: 0.82), Color(red: 0.82, green: 0.90, blue: 1.0), Color(red: 0.96, green: 0.96, blue: 0.98)]
    }
}

#Preview("Forecast") {
    let settings = InMemorySettingsStore(state: SharedAppState(locations: [PreviewFixtures.sampleLocation]))
    let cache = InMemoryForecastCache(snapshots: [
        PreviewFixtures.sampleLocationID: .fromSuccessful(bundle: PreviewFixtures.sampleBundle()),
    ])
    let model = AppModel(
        settingsStore: settings,
        forecastCache: cache,
        credentialStore: InMemoryCredentialStore(apiKey: "preview-not-a-real-key")
    )
    return ForecastDetailView(location: PreviewFixtures.sampleLocation)
        .environmentObject(model)
        .frame(width: 900, height: 700)
}
