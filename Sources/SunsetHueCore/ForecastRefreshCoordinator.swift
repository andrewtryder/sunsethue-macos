import Foundation
import WidgetKit

/// Sole writer of forecast cache snapshots. Owns networking + Keychain reads for refresh.
public actor ForecastRefreshCoordinator {
    private let settingsStore: any SharedSettingsStore
    private let forecastCache: any ForecastCache
    private let credentialStore: CredentialStore
    private let forecastService: ForecastService
    private var scheduledTask: Task<Void, Never>?
    private var isRefreshingAll = false

    public init(
        settingsStore: any SharedSettingsStore = SharedStorageFactory.makeSettingsStore(),
        forecastCache: any ForecastCache = SharedStorageFactory.makeForecastCache(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        forecastService: ForecastService = ForecastService()
    ) {
        self.settingsStore = settingsStore
        self.forecastCache = forecastCache
        self.credentialStore = credentialStore
        self.forecastService = forecastService
    }

    public func refreshLocation(id: UUID, force: Bool) async -> CachedLocationSnapshot? {
        let state = (try? await settingsStore.load()) ?? SharedAppState()
        guard let location = state.locations.first(where: { $0.id == id }) else { return nil }
        return await refresh(location: location, force: force)
    }

    public func refreshAllStaleLocations() async {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }

        let state = (try? await settingsStore.load()) ?? SharedAppState()
        for location in state.locations {
            let existing = try? await forecastCache.loadSnapshot(for: location.id)
            let needsRefresh = forceNeeded(existing: existing, location: location)
            if needsRefresh {
                _ = await refresh(location: location, force: false)
            }
        }
        await scheduleNextRefresh()
    }

    public func scheduleNextRefresh() async {
        scheduledTask?.cancel()
        let state = (try? await settingsStore.load()) ?? SharedAppState()
        let now = Date()
        var nextDates: [Date] = []
        for location in state.locations {
            let snapshot = try? await forecastCache.loadSnapshot(for: location.id)
            let hours = location.refreshIntervalHours
            let anchor = snapshot?.fetchedAt ?? now.addingTimeInterval(-TimeInterval(hours * 3600))
            let due = anchor.addingTimeInterval(TimeInterval(hours * 3600))
            if due > now {
                nextDates.append(due)
            } else {
                nextDates.append(now.addingTimeInterval(60))
            }
        }
        guard let soonest = nextDates.min() else { return }
        let delay = max(60, soonest.timeIntervalSince(now))
        scheduledTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await refreshAllStaleLocations()
        }
    }

    public func applicationDidWake() async {
        await refreshAllStaleLocations()
    }

    private func forceNeeded(existing: CachedLocationSnapshot?, location: SavedLocation) -> Bool {
        guard let existing else { return true }
        switch existing.status {
        case .authenticationRequired:
            return true
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > Date() { return false }
            return true
        case .current:
            return !existing.isFresh(refreshIntervalHours: location.refreshIntervalHours)
        case .stale, .temporarilyUnavailable:
            return true
        }
    }

    private func refresh(location: SavedLocation, force: Bool) async -> CachedLocationSnapshot? {
        let previous = try? await forecastCache.loadSnapshot(for: location.id)
        if !force, let previous, previous.isFresh(refreshIntervalHours: location.refreshIntervalHours) {
            return previous
        }

        let attemptedAt = Date()
        let apiKey: String
        do {
            guard let loaded = try credentialStore.loadAPIKey(), !loaded.isEmpty else {
                let snapshot = makeFailureSnapshot(
                    locationID: location.id,
                    previous: previous,
                    attemptedAt: attemptedAt,
                    status: .authenticationRequired
                )
                try? await forecastCache.saveSnapshot(snapshot)
                reloadWidgets()
                return snapshot
            }
            apiKey = loaded
        } catch {
            let snapshot = makeFailureSnapshot(
                locationID: location.id,
                previous: previous,
                attemptedAt: attemptedAt,
                status: .authenticationRequired
            )
            try? await forecastCache.saveSnapshot(snapshot)
            reloadWidgets()
            return snapshot
        }

        let outcome = await forecastService.refreshPreservingCache(
            location: location,
            apiKey: apiKey,
            previous: previous?.bundle
        )

        let snapshot: CachedLocationSnapshot
        if let bundle = outcome.bundle, !outcome.usedCache {
            snapshot = CachedLocationSnapshot.fromSuccessful(bundle: bundle, attemptedAt: attemptedAt)
        } else if let error = outcome.error {
            let status = status(from: error)
            snapshot = makeFailureSnapshot(
                locationID: location.id,
                previous: previous,
                forecasts: outcome.bundle?.forecasts ?? previous?.forecasts ?? [],
                fetchedAt: outcome.bundle?.fetchedAt ?? previous?.fetchedAt ?? attemptedAt,
                attemptedAt: attemptedAt,
                status: status
            )
        } else if let bundle = outcome.bundle {
            snapshot = CachedLocationSnapshot(
                locationID: location.id,
                fetchedAt: bundle.fetchedAt,
                lastAttemptAt: attemptedAt,
                forecasts: bundle.forecasts,
                status: .stale
            )
        } else {
            snapshot = makeFailureSnapshot(
                locationID: location.id,
                previous: previous,
                attemptedAt: attemptedAt,
                status: .temporarilyUnavailable
            )
        }

        try? await forecastCache.saveSnapshot(snapshot)
        reloadWidgets()
        return snapshot
    }

    private func status(from error: SunsetHueError) -> RefreshStatus {
        switch error {
        case .authentication, .missingCredentials:
            return .authenticationRequired
        case .rateLimited(let retryAfter):
            let date = retryAfter.map { Date().addingTimeInterval(TimeInterval($0)) }
            return .rateLimited(retryAfter: date)
        default:
            return .temporarilyUnavailable
        }
    }

    private func makeFailureSnapshot(
        locationID: UUID,
        previous: CachedLocationSnapshot?,
        forecasts: [EventForecast]? = nil,
        fetchedAt: Date? = nil,
        attemptedAt: Date,
        status: RefreshStatus
    ) -> CachedLocationSnapshot {
        CachedLocationSnapshot(
            locationID: locationID,
            fetchedAt: fetchedAt ?? previous?.fetchedAt ?? attemptedAt,
            lastAttemptAt: attemptedAt,
            forecasts: forecasts ?? previous?.forecasts ?? [],
            status: status
        )
    }

    private nonisolated func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: SunsetHueConstants.widgetKind)
    }
}
