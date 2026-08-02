import WidgetKit
import SunsetHueCore

struct SunsetHueEntry: TimelineEntry {
    enum Kind {
        case placeholder
        case onboarding
        case forecast
        case cached
        case authentication
        case unavailable
    }

    let date: Date
    let kind: Kind
    let location: SavedLocation?
    let bundle: LocationForecastBundle?
    let configuration: SunsetHueWidgetConfigurationIntent
    let statusMessage: String?
}

struct SunsetHueTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = SunsetHueEntry
    typealias Intent = SunsetHueWidgetConfigurationIntent

    private let settingsStore = SharedStorageFactory.makeSettingsStore()
    private let forecastCache = SharedStorageFactory.makeForecastCache()
    private let credentialStore = KeychainCredentialStore()
    private let forecastService = ForecastService()
    private let dateCalculator = ForecastDateCalculator()

    func placeholder(in context: Context) -> SunsetHueEntry {
        SunsetHueEntry(
            date: Date(),
            kind: .placeholder,
            location: PreviewFixtures.sampleLocation,
            bundle: PreviewFixtures.sampleBundle(),
            configuration: SunsetHueWidgetConfigurationIntent(),
            statusMessage: nil
        )
    }

    func snapshot(for configuration: SunsetHueWidgetConfigurationIntent, in context: Context) async -> SunsetHueEntry {
        await makeEntry(for: configuration, date: Date(), allowNetwork: !context.isPreview)
    }

    func timeline(for configuration: SunsetHueWidgetConfigurationIntent, in context: Context) async -> Timeline<SunsetHueEntry> {
        let now = Date()
        let entry = await makeEntry(for: configuration, date: now, allowNetwork: true)
        let reload = nextReloadDate(for: entry, now: now)
        return Timeline(entries: [entry], policy: .after(reload))
    }

    private func makeEntry(
        for configuration: SunsetHueWidgetConfigurationIntent,
        date: Date,
        allowNetwork: Bool
    ) async -> SunsetHueEntry {
        let state = (try? settingsStore.load()) ?? SharedAppState()
        guard !state.locations.isEmpty else {
            return SunsetHueEntry(
                date: date,
                kind: .onboarding,
                location: nil,
                bundle: nil,
                configuration: configuration,
                statusMessage: "Open SunsetHue to add a location."
            )
        }

        let location = resolveLocation(configuration: configuration, state: state)
        guard let location else {
            return SunsetHueEntry(
                date: date,
                kind: .onboarding,
                location: nil,
                bundle: nil,
                configuration: configuration,
                statusMessage: "Choose a location in the widget settings."
            )
        }

        let cached = try? forecastCache.loadBundle(for: location.id)

        guard allowNetwork else {
            return SunsetHueEntry(
                date: date,
                kind: cached == nil ? .placeholder : .cached,
                location: location,
                bundle: cached ?? PreviewFixtures.sampleBundle(),
                configuration: configuration,
                statusMessage: cached == nil ? nil : "Last updated"
            )
        }

        do {
            guard let apiKey = try credentialStore.loadAPIKey(), !apiKey.isEmpty else {
                return SunsetHueEntry(
                    date: date,
                    kind: .authentication,
                    location: location,
                    bundle: cached,
                    configuration: configuration,
                    statusMessage: "Open SunsetHue to update API key."
                )
            }

            let outcome = await forecastService.refreshPreservingCache(
                location: location,
                apiKey: apiKey,
                previous: cached,
                now: date
            )

            if let error = outcome.error, error.isAuthenticationFailure {
                return SunsetHueEntry(
                    date: date,
                    kind: .authentication,
                    location: location,
                    bundle: outcome.bundle,
                    configuration: configuration,
                    statusMessage: "Open SunsetHue to update API key."
                )
            }

            if let bundle = outcome.bundle, !outcome.usedCache {
                try? forecastCache.saveBundle(bundle)
                var updated = state
                updated.lastSuccessfulUpdate = bundle.fetchedAt
                updated.lastErrorMessage = nil
                updated.lastErrorIsAuthentication = false
                try? settingsStore.save(updated)
                return SunsetHueEntry(
                    date: date,
                    kind: .forecast,
                    location: location,
                    bundle: bundle,
                    configuration: configuration,
                    statusMessage: nil
                )
            }

            if let bundle = outcome.bundle, outcome.usedCache {
                return SunsetHueEntry(
                    date: date,
                    kind: .cached,
                    location: location,
                    bundle: bundle,
                    configuration: configuration,
                    statusMessage: "Last updated \(bundle.fetchedAt.formatted(date: .omitted, time: .shortened))"
                )
            }

            return SunsetHueEntry(
                date: date,
                kind: .unavailable,
                location: location,
                bundle: nil,
                configuration: configuration,
                statusMessage: outcome.error?.userMessage ?? "Forecast unavailable."
            )
        } catch {
            return SunsetHueEntry(
                date: date,
                kind: cached == nil ? .unavailable : .cached,
                location: location,
                bundle: cached,
                configuration: configuration,
                statusMessage: cached == nil
                    ? SunsetHueError.networkUnavailable.userMessage
                    : "Last updated"
            )
        }
    }

    private func resolveLocation(
        configuration: SunsetHueWidgetConfigurationIntent,
        state: SharedAppState
    ) -> SavedLocation? {
        if let id = configuration.location?.id {
            return state.locations.first(where: { $0.id == id })
        }
        return state.selectedLocation ?? state.locations.first
    }

    private func nextReloadDate(for entry: SunsetHueEntry, now: Date) -> Date {
        guard let location = entry.location, let timeZone = location.timeZone else {
            return now.addingTimeInterval(TimeInterval(SunsetHueConstants.minTimelineReloadSeconds))
        }
        var retryAfter: Int?
        if case .authentication = entry.kind {
            retryAfter = SunsetHueConstants.minTimelineReloadSeconds
        }
        return dateCalculator.preferredTimelineReload(
            refreshIntervalHours: location.refreshIntervalHours,
            timeZone: timeZone,
            now: now,
            rateLimitRetryAfter: retryAfter
        )
    }
}
