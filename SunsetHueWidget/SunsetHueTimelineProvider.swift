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

    init(
        date: Date,
        kind: Kind,
        location: SavedLocation?,
        bundle: LocationForecastBundle?,
        configuration: SunsetHueWidgetConfigurationIntent,
        statusMessage: String?
    ) {
        self.date = date
        self.kind = kind
        self.location = location
        self.bundle = bundle
        self.configuration = configuration
        self.statusMessage = statusMessage
    }

    init(
        date: Date,
        model: WidgetTimelineEntryModel,
        configuration: SunsetHueWidgetConfigurationIntent
    ) {
        self.date = date
        self.kind = Kind(model.kind)
        self.location = model.location
        self.bundle = model.bundle
        self.configuration = configuration
        self.statusMessage = model.statusMessage
    }
}

private extension SunsetHueEntry.Kind {
    init(_ kind: WidgetTimelineEntryModel.Kind) {
        switch kind {
        case .placeholder: self = .placeholder
        case .onboarding: self = .onboarding
        case .forecast: self = .forecast
        case .cached: self = .cached
        case .stale: self = .stale
        case .authentication: self = .authentication
        case .unavailable: self = .unavailable
        }
    }
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
        if context.isPreview {
            return placeholder(in: context)
        }
        return await makeEntry(for: configuration, date: Date())
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
        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        guard !state.locations.isEmpty else {
            return SunsetHueEntry(
                date: date,
                model: WidgetTimelineEntryBuilder.makeOnboarding(message: "Open SunsetHue to add a location."),
                configuration: configuration
            )
        }

        let location = resolveLocation(configuration: configuration, state: state)
        guard let location else {
            return SunsetHueEntry(
                date: date,
                model: WidgetTimelineEntryBuilder.makeOnboarding(message: "Choose a location in the widget settings."),
                configuration: configuration
            )
        }

        let snapshot = try? await forecastCache.loadSnapshot(for: location.id)
        let model = WidgetTimelineEntryBuilder.makeEntry(location: location, snapshot: snapshot, now: date)
        var entry = SunsetHueEntry(date: date, model: model, configuration: configuration)
        if model.kind == .forecast, let bundle = model.bundle {
            entry = SunsetHueEntry(
                date: date,
                kind: .forecast,
                location: location,
                bundle: bundle,
                configuration: configuration,
                statusMessage: WidgetUpdatedCopy.compactUpdated(from: bundle.fetchedAt, now: date)
            )
        } else if model.kind == .stale, let fetchedAt = snapshot?.fetchedAt, model.bundle != nil {
            entry = SunsetHueEntry(
                date: date,
                kind: .stale,
                location: location,
                bundle: model.bundle,
                configuration: configuration,
                statusMessage: WidgetUpdatedCopy.compactUpdated(from: fetchedAt, now: date)
            )
        }
        return entry
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
