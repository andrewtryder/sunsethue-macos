import Foundation
import os

private struct RefreshExecutionResult: Sendable {
    let snapshot: CachedLocationSnapshot?
    let performedNetworkRefresh: Bool
}

/// Sole writer of forecast cache snapshots. Owns networking + Keychain reads for refresh.
public actor ForecastRefreshCoordinator {
    public let activityRecorder: RefreshActivityRecorder
    private let settingsStore: any SharedSettingsStore
    private let forecastCache: any ForecastCache
    private let credentialStore: CredentialStore
    private let forecastService: ForecastService
    private let sideEffectSink: any ForecastRefreshSideEffectSink
    private let logger = Logger(subsystem: "com.andrewtryder.SunsetHue", category: "Coordinator")
    private var scheduledTask: Task<Void, Never>?
    private var isRefreshingAll = false
    private var inFlightRefreshes: [UUID: Task<RefreshExecutionResult, Never>] = [:]

    public init(
        settingsStore: any SharedSettingsStore = SharedStorageFactory.makeSettingsStore(),
        forecastCache: any ForecastCache = SharedStorageFactory.makeForecastCache(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        forecastService: ForecastService = ForecastService(),
        sideEffectSink: any ForecastRefreshSideEffectSink = NoOpForecastRefreshSideEffectSink(),
        activityRecorder: RefreshActivityRecorder = RefreshActivityRecorder()
    ) {
        self.settingsStore = settingsStore
        self.forecastCache = forecastCache
        self.credentialStore = credentialStore
        self.forecastService = forecastService
        self.sideEffectSink = sideEffectSink
        self.activityRecorder = activityRecorder
    }

    public func refreshLocation(id: UUID, force: Bool, trigger: RefreshTrigger = .manual) async -> CachedLocationSnapshot? {
        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        guard let location = state.locations.first(where: { $0.id == id }) else { return nil }
        return await refresh(location: location, force: force, trigger: trigger)
    }

    public func refreshAllStaleLocations(trigger: RefreshTrigger = .scheduled) async {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }

        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        for location in state.locations {
            let existing = try? await forecastCache.loadSnapshot(for: location.id)
            let needsRefresh = forceNeeded(existing: existing, location: location, force: false)
            if needsRefresh {
                _ = await refresh(location: location, force: false, trigger: trigger)
            }
        }
        await scheduleNextRefresh()
    }

    /// Force-refresh every location currently marked authentication-required (e.g. after saving a new API key).
    public func refreshAuthenticationRequiredLocations(trigger: RefreshTrigger = .apiKeyChanged) async {
        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        for location in state.locations {
            let existing = try? await forecastCache.loadSnapshot(for: location.id)
            guard existing?.status == .authenticationRequired else { continue }
            _ = await refresh(location: location, force: true, trigger: trigger)
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
            if let snapshot {
                if snapshot.status == .current && !snapshot.hasOperationalCoverage(for: location, now: now) {
                    nextDates.append(now)
                } else if let next = snapshot.nextScheduledRefresh(
                    refreshIntervalHours: location.refreshIntervalHours,
                    timeZone: location.timeZone,
                    now: now
                ), next > now {
                    nextDates.append(next)
                }
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
        await refreshAllStaleLocations(trigger: .didWake)
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
            let isFresh = existing.isFresh(refreshIntervalHours: location.refreshIntervalHours, now: now)
            let hasCoverage = existing.hasOperationalCoverage(for: location, now: now)
            return !isFresh || !hasCoverage
        case .stale:
            if let next = existing.nextAttemptAt, next > now { return false }
            return true
        case .temporarilyUnavailable, .invalidResponse:
            if let next = existing.nextAttemptAt, next > now { return false }
            return true
        }
    }

    private func refresh(location: SavedLocation, force: Bool, trigger: RefreshTrigger) async -> CachedLocationSnapshot? {
        let locationID = location.id

        if let existingTask = inFlightRefreshes[locationID] {
            let joinedResult = await existingTask.value
            if joinedResult.performedNetworkRefresh || !force {
                return joinedResult.snapshot
            }
            if let nextTask = inFlightRefreshes[locationID], nextTask != existingTask {
                let nextResult = await nextTask.value
                return nextResult.snapshot
            }
        }

        let task = Task<RefreshExecutionResult, Never> {
            await self.performRefresh(location: location, force: force, trigger: trigger)
        }
        inFlightRefreshes[locationID] = task
        defer {
            if inFlightRefreshes[locationID] == task {
                inFlightRefreshes.removeValue(forKey: locationID)
            }
        }
        let result = await task.value
        return result.snapshot
    }

    private func performRefresh(location: SavedLocation, force: Bool, trigger: RefreshTrigger) async -> RefreshExecutionResult {
        let previous = try? await forecastCache.loadSnapshot(for: location.id)
        let now = Date()

        if !force {
            if let previous, !forceNeeded(existing: previous, location: location, force: false) {
                await activityRecorder.record(
                    locationID: location.id,
                    locationName: location.name,
                    trigger: trigger,
                    result: .skippedFresh,
                    details: "Forecast is fresh"
                )
                return RefreshExecutionResult(snapshot: previous, performedNetworkRefresh: false)
            }
        } else if let previous,
                  case .rateLimited(let retryAfter) = previous.status,
                  let retryAfter, retryAfter > now {
            // Manual refresh still respects an active rate-limit deadline.
            await activityRecorder.record(
                locationID: location.id,
                locationName: location.name,
                trigger: trigger,
                result: .rateLimited,
                details: "Active rate limit deadline"
            )
            return RefreshExecutionResult(snapshot: previous, performedNetworkRefresh: false)
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
                let outcome = await persistAndEmitSideEffects(
                    location: location,
                    previous: previous,
                    candidate: snapshot,
                    wasSuccessfulNetworkRefresh: false
                )
                let savedSnapshot: CachedLocationSnapshot?
                switch outcome {
                case .committed(let s), .rejectedStale(let s):
                    savedSnapshot = s
                    await activityRecorder.record(
                        locationID: location.id,
                        locationName: location.name,
                        trigger: trigger,
                        result: .authenticationRequired,
                        details: "API key not configured"
                    )
                case .failed(let fallback):
                    savedSnapshot = fallback
                    await activityRecorder.record(
                        locationID: location.id,
                        locationName: location.name,
                        trigger: trigger,
                        result: .persistenceFailure,
                        details: "Cache persistence failed"
                    )
                }
                return RefreshExecutionResult(snapshot: savedSnapshot, performedNetworkRefresh: false)
            }
            apiKey = loaded
        } catch {
            let snapshot = makeFailureSnapshot(
                locationID: location.id,
                previous: previous,
                attemptedAt: attemptedAt,
                status: .authenticationRequired
            )
            let outcome = await persistAndEmitSideEffects(
                location: location,
                previous: previous,
                candidate: snapshot,
                wasSuccessfulNetworkRefresh: false
            )
            let savedSnapshot: CachedLocationSnapshot?
            switch outcome {
            case .committed(let s), .rejectedStale(let s):
                savedSnapshot = s
                await activityRecorder.record(
                    locationID: location.id,
                    locationName: location.name,
                    trigger: trigger,
                    result: .authenticationRequired,
                    details: "Keychain credentials unavailable"
                )
            case .failed(let fallback):
                savedSnapshot = fallback
                await activityRecorder.record(
                    locationID: location.id,
                    locationName: location.name,
                    trigger: trigger,
                    result: .persistenceFailure,
                    details: "Cache persistence failed"
                )
            }
            return RefreshExecutionResult(snapshot: savedSnapshot, performedNetworkRefresh: false)
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

        let persistenceOutcome = await persistAndEmitSideEffects(
            location: location,
            previous: previous,
            candidate: snapshot,
            wasSuccessfulNetworkRefresh: wasSuccessfulNetworkRefresh
        )

        let savedSnapshot: CachedLocationSnapshot?
        switch persistenceOutcome {
        case .failed(let fallback):
            savedSnapshot = fallback
            await activityRecorder.record(
                locationID: location.id,
                locationName: location.name,
                trigger: trigger,
                result: .persistenceFailure,
                details: "Cache persistence failed"
            )
        case .rejectedStale(let authoritative):
            savedSnapshot = authoritative
            await activityRecorder.record(
                locationID: location.id,
                locationName: location.name,
                trigger: trigger,
                result: .skippedFresh,
                details: "Authoritative snapshot is newer"
            )
        case .committed(let saved):
            savedSnapshot = saved
            if wasSuccessfulNetworkRefresh {
                await activityRecorder.record(
                    locationID: location.id,
                    locationName: location.name,
                    trigger: trigger,
                    result: .refreshedSuccessfully,
                    details: "Updated \(snapshot.forecasts.count) forecasts"
                )
            } else {
                let resultSummary: RefreshResultSummary
                switch snapshot.status {
                case .authenticationRequired: resultSummary = .authenticationRequired
                case .rateLimited: resultSummary = .rateLimited
                case .invalidRequest: resultSummary = .invalidRequest
                case .temporarilyUnavailable, .invalidResponse, .stale: resultSummary = .transientFailure
                case .current: resultSummary = .refreshedSuccessfully
                }
                await activityRecorder.record(
                    locationID: location.id,
                    locationName: location.name,
                    trigger: trigger,
                    result: resultSummary,
                    details: outcome.error?.userMessage
                )
            }
        }

        return RefreshExecutionResult(snapshot: savedSnapshot, performedNetworkRefresh: true)
    }

    private enum PersistenceOutcome: Sendable {
        case committed(CachedLocationSnapshot)
        case rejectedStale(CachedLocationSnapshot)
        case failed(fallback: CachedLocationSnapshot?)
    }

    private func persistAndEmitSideEffects(
        location: SavedLocation,
        previous: CachedLocationSnapshot?,
        candidate: CachedLocationSnapshot,
        wasSuccessfulNetworkRefresh: Bool
    ) async -> PersistenceOutcome {
        do {
            let result = try await forecastCache.saveSnapshot(candidate)
            switch result {
            case .committed(let snapshot):
                await emitSideEffect(
                    location: location,
                    previous: previous,
                    current: snapshot,
                    wasSuccessfulNetworkRefresh: wasSuccessfulNetworkRefresh
                )
                return .committed(snapshot)
            case .rejectedStale(let authoritative):
                return .rejectedStale(authoritative)
            }
        } catch {
            logger.error("Failed to persist forecast cache for location \(location.id): \(error.localizedDescription, privacy: .public)")
            return .failed(fallback: previous)
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
