import WidgetKit
import SwiftUI
import SunsetHueCore

struct SunsetHueWidget: Widget {
    let kind = "SunsetHueWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SunsetHueWidgetConfigurationIntent.self,
            provider: SunsetHueTimelineProvider()
        ) { entry in
            SunsetHueWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetAtmosphereBackground()
                }
                .widgetURL(widgetURL(for: entry))
        }
        .configurationDisplayName("SunsetHue")
        .description("Sunrise and sunset forecast quality.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }

    private func widgetURL(for entry: SunsetHueEntry) -> URL {
        if let id = entry.location?.id {
            return DeepLink.locationURL(id: id)
        }
        return DeepLink.openAppURL()
    }
}

struct SunsetHueWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SunsetHueEntry

    var body: some View {
        switch entry.kind {
        case .onboarding:
            OnboardingWidgetView(message: entry.statusMessage ?? "Open SunsetHue to get started.")
        case .authentication:
            AuthWidgetView(locationName: entry.location?.name, message: entry.statusMessage)
        case .unavailable:
            OnboardingWidgetView(message: entry.statusMessage ?? "Forecast unavailable.")
        default:
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemMedium:
                MediumWidgetView(entry: entry)
            default:
                LargeWidgetView(entry: entry)
            }
        }
    }
}

struct OnboardingWidgetView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sun.horizon.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
            Text("SunsetHue")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AuthWidgetView: View {
    let locationName: String?
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(locationName ?? "SunsetHue", systemImage: "key.slash")
                .font(.headline)
            Text(message ?? "Open SunsetHue to update API key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel(message ?? "Open SunsetHue to update API key.")
    }
}

struct SmallWidgetView: View {
    let entry: SunsetHueEntry

    var body: some View {
        if let content = WidgetContentResolver.resolve(entry: entry, preferSingle: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(content.locationName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                HStack {
                    Image(systemName: content.primary.eventType == .sunrise ? "sunrise.fill" : "sunset.fill")
                        .foregroundStyle(content.primary.eventType == .sunrise ? .orange : .pink)
                    Text(content.dayLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(content.primary.qualityLabel)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                Text(content.primary.timeLabel)
                    .font(.subheadline.monospacedDigit())
                Text(content.primary.qualityText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let status = entry.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(content.accessibilityLabel)
        } else {
            OnboardingWidgetView(message: entry.statusMessage ?? "No data")
        }
    }
}

struct MediumWidgetView: View {
    let entry: SunsetHueEntry

    var body: some View {
        if let content = WidgetContentResolver.resolve(entry: entry, preferSingle: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(content.locationName)
                        .font(.headline)
                    Spacer()
                    if let status = entry.statusMessage {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    ForEach(content.events, id: \.eventType) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(event.eventType.displayName, systemImage: event.eventType == .sunrise ? "sunrise.fill" : "sunset.fill")
                                .font(.caption.weight(.semibold))
                            Text(event.qualityLabel)
                                .font(.title2.weight(.bold))
                            Text(event.timeLabel)
                                .font(.caption.monospacedDigit())
                            Text(event.magicLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let tomorrow = content.tomorrowSummary {
                    Text(tomorrow)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            OnboardingWidgetView(message: entry.statusMessage ?? "No data")
        }
    }
}

struct LargeWidgetView: View {
    let entry: SunsetHueEntry

    var body: some View {
        if let location = entry.location, let bundle = entry.bundle, let timeZone = location.timeZone {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(location.name)
                        .font(.headline)
                    Spacer()
                    if let status = entry.statusMessage {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(0..<min(3, location.forecastDays), id: \.self) { dayOffset in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PresentationFormatting.relativeDayLabel(dayOffset: dayOffset, timeZone: timeZone))
                            .font(.subheadline.weight(.semibold))
                        ForEach(EventType.allCases, id: \.self) { eventType in
                            if shouldShow(eventType),
                               let forecast = bundle.forecast(dayOffset: dayOffset, eventType: eventType, timeZone: timeZone) {
                                LargeEventRow(forecast: forecast, timeZone: timeZone)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            OnboardingWidgetView(message: entry.statusMessage ?? "No data")
        }
    }

    private func shouldShow(_ eventType: EventType) -> Bool {
        switch entry.configuration.eventMode {
        case .sunrise: return eventType == .sunrise
        case .sunset: return eventType == .sunset
        case .both: return true
        }
    }
}

struct LargeEventRow: View {
    let forecast: EventForecast
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: forecast.eventType == .sunrise ? "sunrise.fill" : "sunset.fill")
                .foregroundStyle(forecast.eventType == .sunrise ? .orange : .pink)
                .frame(width: 16)
            Text(forecast.eventType.displayName)
                .frame(width: 58, alignment: .leading)
            Text(PresentationFormatting.percentage(fromNormalized: forecast.quality) ?? "n/a")
                .fontWeight(.semibold)
                .frame(width: 52, alignment: .leading)
            Text(PresentationFormatting.timeString(forecast.eventTime, timeZone: timeZone) ?? "—")
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)
            Text(PresentationFormatting.percentage(fromNormalized: forecast.cloudCover).map { "Cloud \($0)" } ?? "Cloud —")
                .foregroundStyle(.secondary)
            Spacer()
            Text(goldenLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private var goldenLabel: String {
        guard let window = forecast.goldenHour,
              let start = PresentationFormatting.timeString(window.start, timeZone: timeZone),
              let end = PresentationFormatting.timeString(window.end, timeZone: timeZone) else {
            return "Golden —"
        }
        return "Golden \(start)–\(end)"
    }
}

struct WidgetAtmosphereBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.24, green: 0.14, blue: 0.18)]
                : [Color(red: 1.0, green: 0.94, blue: 0.86), Color(red: 0.85, green: 0.91, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
