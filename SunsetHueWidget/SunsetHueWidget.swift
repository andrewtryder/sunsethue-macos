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
