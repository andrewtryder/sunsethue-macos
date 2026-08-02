import WidgetKit
import SunsetHueCore

struct SunsetHueEntry: TimelineEntry {
    enum Kind {
        case placeholder
        case onboarding
        case forecast
        case cached
        case stale
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
        await makeEntry(for: configuration, date: Date())
    }

    func timeline(for configuration: SunsetHueWidgetConfigurationIntent, in context: Context) async -> Timeline<SunsetHueEntry> {
        let now = Date()
        let entry = await makeEntry(for: configuration, date: now)

        if entry.kind == .authentication {
            return Timeline(entries: [entry], policy: .never)
        }

        let reload = nextReloadDate(for: entry, now: now)
        let displayDates = timelineDates(for: entry, now: now, until: reload)
        let entries = displayDates.map { date in
            SunsetHueEntry(
                date: date,
                kind: entry.kind,
                location: entry.location,
                bundle: entry.bundle,
                configuration: entry.configuration,
                statusMessage: entry.statusMessage
            )
        }
        return Timeline(entries: entries.isEmpty ? [entry] : entries, policy: .after(reload))
    }

    private func makeEntry(
        for configuration: SunsetHueWidgetConfigurationIntent,
        date: Date
    ) async -> SunsetHueEntry {
        let state = (try? await settingsStore.load()) ?? SharedAppState()
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

        let snapshot = try? await forecastCache.loadSnapshot(for: location.id)
        let bundle = snapshot?.bundle

        guard let snapshot else {
            return SunsetHueEntry(
                date: date,
                kind: contextPreviewKind(configuration: configuration),
                location: location,
                bundle: PreviewFixtures.sampleBundle(),
                configuration: configuration,
                statusMessage: "Open SunsetHue to refresh"
            )
        }

        switch snapshot.status {
        case .authenticationRequired:
            return SunsetHueEntry(
                date: date,
                kind: .authentication,
                location: location,
                bundle: bundle,
                configuration: configuration,
                statusMessage: "Open SunsetHue to update the API key"
            )
        case .current where snapshot.isFresh(refreshIntervalHours: location.refreshIntervalHours, now: date):
            return SunsetHueEntry(
                date: date,
                kind: .forecast,
                location: location,
                bundle: bundle,
                configuration: configuration,
                statusMessage: nil
            )
        case .current, .stale, .rateLimited, .temporarilyUnavailable:
            let ageHours = max(1, Int(date.timeIntervalSince(snapshot.fetchedAt) / 3600))
            let message: String
            if case .authenticationRequired = snapshot.status {
                message = "Open SunsetHue to update the API key"
            } else if bundle == nil {
                message = snapshot.status == .temporarilyUnavailable
                    ? "Forecast unavailable — Open SunsetHue"
                    : "Open SunsetHue to refresh"
            } else {
                message = "Updated \(ageHours) hour\(ageHours == 1 ? "" : "s") ago — Open SunsetHue to refresh"
            }
            return SunsetHueEntry(
                date: date,
                kind: bundle == nil ? .unavailable : .stale,
                location: location,
                bundle: bundle ?? PreviewFixtures.sampleBundle(),
                configuration: configuration,
                statusMessage: message
            )
        }
    }

    private func contextPreviewKind(configuration: SunsetHueWidgetConfigurationIntent) -> SunsetHueEntry.Kind {
        .placeholder
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
        let jitter = SunsetHueConstants.timelineJitterSeconds(for: location.id)
        return dateCalculator.preferredTimelineReload(
            refreshIntervalHours: location.refreshIntervalHours,
            timeZone: timeZone,
            now: now,
            rateLimitRetryAfter: nil,
            jitterSeconds: jitter,
            cacheFetchedAt: entry.bundle?.fetchedAt
        )
    }

    private func timelineDates(for entry: SunsetHueEntry, now: Date, until reloadDate: Date) -> [Date] {
        guard let location = entry.location, let timeZone = location.timeZone else {
            return [now]
        }
        return dateCalculator.timelineDisplayDates(
            bundle: entry.bundle,
            timeZone: timeZone,
            now: now,
            until: reloadDate
        )
    }
}
