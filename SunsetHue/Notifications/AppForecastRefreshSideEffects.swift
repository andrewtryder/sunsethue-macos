import Foundation
import SunsetHueCore

/// Allows constructing `ForecastRefreshCoordinator` before `AppModel` finishes wiring side effects.
final class ForecastRefreshSideEffectBox: ForecastRefreshSideEffectSink, @unchecked Sendable {
    var impl: (any ForecastRefreshSideEffectSink)?

    func didPersistSnapshot(
        location: SavedLocation,
        previous: CachedLocationSnapshot?,
        current: CachedLocationSnapshot,
        wasSuccessfulNetworkRefresh: Bool
    ) async {
        await impl?.didPersistSnapshot(
            location: location,
            previous: previous,
            current: current,
            wasSuccessfulNetworkRefresh: wasSuccessfulNetworkRefresh
        )
    }
}

/// App-target sink: reload widgets, evaluate threshold alerts, reschedule daily summaries.
final class AppForecastRefreshSideEffects: ForecastRefreshSideEffectSink, @unchecked Sendable {
    private let notificationCoordinator: ForecastNotificationCoordinator
    private let settingsStore: any SharedSettingsStore
    private let forecastCache: any ForecastCache
    private let onSnapshotsChanged: (@Sendable () async -> Void)?

    init(
        notificationCoordinator: ForecastNotificationCoordinator,
        settingsStore: any SharedSettingsStore,
        forecastCache: any ForecastCache,
        onSnapshotsChanged: (@Sendable () async -> Void)? = nil
    ) {
        self.notificationCoordinator = notificationCoordinator
        self.settingsStore = settingsStore
        self.forecastCache = forecastCache
        self.onSnapshotsChanged = onSnapshotsChanged
    }

    func didPersistSnapshot(
        location: SavedLocation,
        previous: CachedLocationSnapshot?,
        current: CachedLocationSnapshot,
        wasSuccessfulNetworkRefresh: Bool
    ) async {
        WidgetReloadStateTracker.shared.recordCacheCommit()
        WidgetReload.timelines()

        await notificationCoordinator.evaluateSuccessfulRefresh(
            location: location,
            previous: previous,
            current: current,
            wasSuccessfulNetworkRefresh: wasSuccessfulNetworkRefresh
        )

        let state = (try? await settingsStore.load())?.value ?? SharedAppState()
        var snapshots: [UUID: CachedLocationSnapshot] = [:]
        for loc in state.locations {
            if loc.id == location.id {
                snapshots[loc.id] = current
            } else if let snap = try? await forecastCache.loadSnapshot(for: loc.id) {
                snapshots[loc.id] = snap
            }
        }
        await notificationCoordinator.rescheduleDailyNotifications(state: state, snapshots: snapshots)
        await onSnapshotsChanged?()
    }
}
