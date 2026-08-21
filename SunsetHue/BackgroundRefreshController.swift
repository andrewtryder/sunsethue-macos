import Foundation
import SunsetHueCore
import os

/// Manages an opportunistic macOS NSBackgroundActivityScheduler for periodic forecast updates.
@MainActor
final class BackgroundRefreshController: ObservableObject {
    static let activityIdentifier = "com.andrewtryder.SunsetHue.forecast-refresh"

    @Published private(set) var lastActivityAt: Date?
    @Published private(set) var lastDisposition: String?
    @Published private(set) var isActive = false

    private let refreshCoordinator: ForecastRefreshCoordinator
    private let logger = Logger(subsystem: "com.andrewtryder.SunsetHue", category: "BackgroundRefresh")
    private var scheduler: NSBackgroundActivityScheduler?

    init(refreshCoordinator: ForecastRefreshCoordinator) {
        self.refreshCoordinator = refreshCoordinator
    }

    deinit {
        scheduler?.invalidate()
    }

    func start() {
        guard scheduler == nil else { return }

        let activity = NSBackgroundActivityScheduler(identifier: Self.activityIdentifier)
        activity.repeats = true
        activity.interval = 30 * 60 // 30 minutes
        activity.tolerance = 15 * 60 // 15 minutes
        activity.qualityOfService = .utility

        activity.schedule { [weak self] completionHandler in
            guard let self else {
                completionHandler(.finished)
                return
            }

            if activity.shouldDefer {
                self.logger.info("Background forecast refresh deferred by system energy management")
                Task { @MainActor in
                    self.lastActivityAt = Date()
                    self.lastDisposition = "deferred"
                }
                completionHandler(.deferred)
                return
            }

            self.logger.info("Starting background forecast refresh")
            Task {
                await self.refreshCoordinator.refreshAllStaleLocations(trigger: .backgroundActivity)
                await MainActor.run {
                    self.lastActivityAt = Date()
                    self.lastDisposition = "finished"
                }
                self.logger.info("Background forecast refresh completed")
                completionHandler(.finished)
            }
        }

        scheduler = activity
        isActive = true
        logger.info("Scheduled NSBackgroundActivityScheduler (\(Self.activityIdentifier, privacy: .public))")
    }

    func stop() {
        scheduler?.invalidate()
        scheduler = nil
        isActive = false
        logger.info("Stopped NSBackgroundActivityScheduler")
    }
}
