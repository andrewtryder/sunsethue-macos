import Foundation
import os
import SunsetHueCore

/// Safe `@unchecked Sendable` invariant: wraps the one-shot system completion handler provided
/// by `NSBackgroundActivityScheduler.schedule`, which Apple's documentation defines as safe to
/// invoke from any thread once the background work finishes.
private struct BackgroundCompletionBox: @unchecked Sendable {
    let finish: (NSBackgroundActivityScheduler.Result) -> Void
}

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

    isolated deinit {
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
            let completion = BackgroundCompletionBox(finish: completionHandler)
            Task { @MainActor [weak self] in
                guard let self else {
                    completion.finish(.finished)
                    return
                }

                if scheduler?.shouldDefer == true {
                    logger.info("Background forecast refresh deferred by system energy management")
                    lastActivityAt = Date()
                    lastDisposition = "deferred"
                    completion.finish(.deferred)
                    return
                }

                logger.info("Starting background forecast refresh")
                await refreshCoordinator.refreshAllStaleLocations(trigger: .backgroundActivity)
                lastActivityAt = Date()
                lastDisposition = "finished"
                logger.info("Background forecast refresh completed")
                completion.finish(.finished)
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
