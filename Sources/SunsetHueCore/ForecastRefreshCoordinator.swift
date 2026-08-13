import Foundation
import os

/// Sole writer of forecast cache snapshots. Owns networking + Keychain reads for refresh.
public actor ForecastRefreshCoordinator {
    private let settingsStore: any SharedSettingsStore
    private let forecastCache: any ForecastCache
    private let credentialStore: CredentialStore
    private let forecastService: ForecastService
    private let sideEffectSink: any ForecastRefreshSideEffectSink
    private let logger = Logger(subsystem: "com.andrewtryder.SunsetHue", category: "Coordinator")
    private var scheduledTask: Task<Void, Never>?
    private var isRefreshingAll = false
    private var inFlightRefreshes: [UUID: Task<CachedLocationSnapshot?, Never>] = [:]

    public init(
        settingsStore: any SharedSettingsStore = SharedStorageFactory.makeSettingsStore(),
        forecastCache: any ForecastCache = SharedStorageFactory.makeForecastCache(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        forecastService: ForecastService = ForecastService(),
        sideEffectSink: any ForecastRefreshSideEffectSink = NoOpForecastRefreshSideEffectSink()
    ) {
        self.settingsStore = settingsStore
        self.forecastCache = forecastCache
        self.credentialStore = credentialStore
        self.forecastService = forecastService
        self.sideEffectSink = sideEffectSink
    }

    public func refreshLocation(id: UUID, force: Bool) async -> CachedLocationSnapshot? {
        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        guard let location = state.locations.first(where: { $0.id == id }) else { return nil }
        return await refresh(location: location, force: force)
    }

    public func refreshAllStaleLocations() async {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }

        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        for location in state.locations {
            let existing = try? await forecastCache.loadSnapshot(for: location.id)
            let needsRefresh = forceNeeded(existing: existing, location: location, force: false)
            if needsRefresh {
                _ = await refresh(location: location, force: false)
            }
        }
        await scheduleNextRefresh()
    }

    /// Force-refresh every location currently marked authentication-required (e.g. after saving a new API key).
    public func refreshAuthenticationRequiredLocations() async {
        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        for location in state.locations {
            let existing = try? await forecastCache.loadSnapshot(for: location.id)
            guard existing?.status == .authenticationRequired else { continue }
            _ = await refresh(location: location, force: true)
        }
        await scheduleNextRefresh()
    }

    /// Mark every cached location as authentication-required while preserving forecast data.
    public func markAllSnapshotsAuthenticationRequired() async {
        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        let attemptedAt = Date()
        for location in state.locations {
            let previous = try? await forecastCache.loadSnapshot(for: location.id)
            let snapshot = CachedLocationSnapshot(
                locationID: location.id,
                fetchedAt: previous?.fetchedAt ?? attemptedAt,
                lastAttemptAt: attemptedAt,
                forecasts: previous?.forecasts ?? [],
                status: .authenticationRequired,
                nextAttemptAt: nil,
                consecutiveFailureCount: previous?.consecutiveFailureCount ?? 0
            )
            _ = await persistAndEmitSideEffects(
                location: location,
                previous: previous,
                candidate: snapshot,
                wasSuccessfulNetworkRefresh: false
            )
        }
    }

    public func scheduleNextRefresh() async {
        scheduledTask?.cancel()
        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        let now = Date()
        var nextDates: [Date] = []
        for location in state.locations {
            let snapshot = try? await forecastCache.loadSnapshot(for: location.id)
            if let snapshot, let next = snapshot.nextScheduledRefresh(
                refreshIntervalHours: location.refreshIntervalHours,
                now: now
            ), next > now {
                nextDates.append(next)
            } else if snapshot == nil {
                // No cache yet: attempt soon once (not a 60s loop on auth failures).
                nextDates.append(now.addingTimeInterval(60))
            }
        }
        guard let soonest = nextDates.min() else { return }
        let delay = max(1, soonest.timeIntervalSince(now))
        scheduledTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await refreshAllStaleLocations()
        }
    }

    public func applicationDidWake() async {
        await refreshAllStaleLocations()
    }

    private func forceNeeded(existing: CachedLocationSnapshot?, location: SavedLocation, force: Bool) -> Bool {
        guard let existing else { return true }
        let now = Date()

        if force {
            if case .rateLimited(let retryAfter) = existing.status,
               let retryAfter, retryAfter > now {
                return false
            }
            return true
        }

        switch existing.status {
        case .authenticationRequired, .invalidRequest:
            return false
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > now { return false }
            if let next = existing.nextAttemptAt, next > now { return false }
            return true
        case .current:
            return !existing.isFresh(refreshIntervalHours: location.refreshIntervalHours, now: now)
        case .stale:
            if let next = existing.nextAttemptAt, next > now { return false }
            return true
        case .temporarilyUnavailable, .invalidResponse:
            if let next = existing.nextAttemptAt, next > now { return false }
            return true
        }
    }

    private func refresh(location: SavedLocation, force: Bool) async -> CachedLocationSnapshot? {
        let locationID = location.id

        if let existingTask = inFlightRefreshes[locationID] {
            return await existingTask.value
        }

        let task = Task<CachedLocationSnapshot?, Never> {
            await self.performRefresh(location: location, force: force)
        }
        inFlightRefreshes[locationID] = task
        let result = await task.value
        inFlightRefreshes.removeValue(forKey: locationID)
        return result
    }

    private func performRefresh(location: SavedLocation, force: Bool) async -> CachedLocationSnapshot? {
        let previous = try? await forecastCache.loadSnapshot(for: location.id)
        let now = Date()

        if !force {
            if let previous, !forceNeeded(existing: previous, location: location, force: false) {
                return previous
            }
        } else if let previous,
                  case .rateLimited(let retryAfter) = previous.status,
                  let retryAfter, retryAfter > now {
            // Manual refresh still respects an active rate-limit deadline.
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
                return await persistAndEmitSideEffects(
                    location: location,
                    previous: previous,
                    candidate: snapshot,
                    wasSuccessfulNetworkRefresh: false
                )
            }
            apiKey = loaded
        } catch {
            let snapshot = makeFailureSnapshot(
                locationID: location.id,
                previous: previous,
                attemptedAt: attemptedAt,
                status: .authenticationRequired
            )
            return await persistAndEmitSideEffects(
                location: location,
                previous: previous,
                candidate: snapshot,
                wasSuccessfulNetworkRefresh: false
            )
        }

        let outcome = await forecastService.refreshPreservingCache(
            location: location,
            apiKey: apiKey,
            previous: previous?.bundle
        )

        let snapshot: CachedLocationSnapshot
        var wasSuccessfulNetworkRefresh = false
        if let bundle = outcome.bundle, !outcome.usedCache {
            snapshot = CachedLocationSnapshot.fromSuccessful(bundle: bundle, attemptedAt: attemptedAt)
            wasSuccessfulNetworkRefresh = snapshot.status == .current
        } else if let error = outcome.error {
            let status = status(from: error)
            let rateLimitRetry: Date?
            if case .rateLimited(let retryAfter) = status {
                rateLimitRetry = retryAfter
            } else {
                rateLimitRetry = nil
            }
            snapshot = makeFailureSnapshot(
                locationID: location.id,
                previous: previous,
                forecasts: outcome.bundle?.forecasts ?? previous?.forecasts ?? [],
                fetchedAt: outcome.bundle?.fetchedAt ?? previous?.fetchedAt ?? attemptedAt,
                attemptedAt: attemptedAt,
                status: status,
                rateLimitRetryAfter: rateLimitRetry
            )
        } else if let bundle = outcome.bundle {
            snapshot = CachedLocationSnapshot(
                locationID: location.id,
                fetchedAt: bundle.fetchedAt,
                lastAttemptAt: attemptedAt,
                forecasts: bundle.forecasts,
                status: .stale,
                nextAttemptAt: attemptedAt.addingTimeInterval(15 * 60),
                consecutiveFailureCount: (previous?.consecutiveFailureCount ?? 0) + 1
            )
        } else {
            snapshot = makeFailureSnapshot(
                locationID: location.id,
                previous: previous,
                attemptedAt: attemptedAt,
                status: .temporarilyUnavailable
            )
        }

        return await persistAndEmitSideEffects(
            location: location,
            previous: previous,
            candidate: snapshot,
            wasSuccessfulNetworkRefresh: wasSuccessfulNetworkRefresh
        )
    }

    private func persistAndEmitSideEffects(
        location: SavedLocation,
        previous: CachedLocationSnapshot?,
        candidate: CachedLocationSnapshot,
        wasSuccessfulNetworkRefresh: Bool
    ) async -> CachedLocationSnapshot? {
        do {
            let result = try await forecastCache.saveSnapshot(candidate)
            let authoritative: CachedLocationSnapshot
            switch result {
            case .committed(let snapshot):
                authoritative = snapshot
            case .rejectedStale(let snapshot):
                authoritative = snapshot
            }
            await emitSideEffect(
                location: location,
                previous: previous,
                current: authoritative,
                wasSuccessfulNetworkRefresh: wasSuccessfulNetworkRefresh
            )
            return authoritative
        } catch {
            logger.error("Failed to persist forecast cache for location \(location.id): \(error.localizedDescription, privacy: .public)")
            return previous
        }
    }

    private func emitSideEffect(
        location: SavedLocation,
        previous: CachedLocationSnapshot?,
        current: CachedLocationSnapshot,
        wasSuccessfulNetworkRefresh: Bool
    ) async {
        await sideEffectSink.didPersistSnapshot(
            location: location,
            previous: previous,
            current: current,
            wasSuccessfulNetworkRefresh: wasSuccessfulNetworkRefresh
        )
    }

    private func status(from error: SunsetHueError) -> RefreshStatus {
        switch error {
        case .authentication, .missingCredentials:
            return .authenticationRequired
        case .rateLimited(let retryAfter):
            let date = retryAfter.map { Date().addingTimeInterval(TimeInterval($0)) }
            return .rateLimited(retryAfter: date)
        case .invalidRequest, .invalidCoordinates, .invalidLocation:
            return .invalidRequest
        case .invalidJSON, .invalidResponse, .oversizedResponse:
            return .invalidResponse
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
        status: RefreshStatus,
        rateLimitRetryAfter: Date? = nil
    ) -> CachedLocationSnapshot {
        let backoff = RefreshBackoff.nextAttempt(
            status: status,
            previousFailureCount: previous?.consecutiveFailureCount ?? 0,
            locationID: locationID,
            from: attemptedAt,
            rateLimitRetryAfter: rateLimitRetryAfter
        )
        return CachedLocationSnapshot(
            locationID: locationID,
            fetchedAt: fetchedAt ?? previous?.fetchedAt ?? attemptedAt,
            lastAttemptAt: attemptedAt,
            forecasts: forecasts ?? previous?.forecasts ?? [],
            status: status,
            nextAttemptAt: backoff.nextAttemptAt,
            consecutiveFailureCount: backoff.consecutiveFailureCount
        )
    }
}
