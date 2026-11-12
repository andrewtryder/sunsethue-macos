import Foundation
@preconcurrency import UserNotifications
import os
import SunsetHueCore

actor ForecastNotificationCoordinator {
    enum AuthorizationState: Equatable, Sendable {
        case notDetermined
        case denied
        case authorized
        case provisional
        case ephemeral
    }

    enum EnsureAuthorizationResult: Equatable, Sendable {
        case authorized
        case denied
        case unavailable
    }

    private let center: any NotificationCenterClienting
    private let unCenter: UNUserNotificationCenter
    private let preferencesStore: any NotificationPreferencesStoring
    private let ledgerStore: NotificationDeliveryLedgerStore
    private let dailyScheduler: DailyNotificationScheduler
    private let logger = Logger(subsystem: "com.andrewtryder.SunsetHue", category: "NotificationCoordinator")

    private(set) var authorizationState: AuthorizationState = .notDetermined

    init(
        center: (any NotificationCenterClienting)? = nil,
        unCenter: UNUserNotificationCenter = .current(),
        preferencesStore: any NotificationPreferencesStoring = NotificationPreferencesStore(),
        ledgerStore: NotificationDeliveryLedgerStore = NotificationDeliveryLedgerStore()
    ) {
        self.center = center ?? SystemNotificationCenterClient(center: unCenter)
        self.unCenter = unCenter
        self.preferencesStore = preferencesStore
        self.ledgerStore = ledgerStore
        self.dailyScheduler = DailyNotificationScheduler(scheduling: UNDailyNotificationScheduling(center: unCenter))
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationState = map(settings.authorizationStatus)
    }

    /// Requests permission when undetermined. Returns whether delivery is allowed.
    @discardableResult
    func ensureAuthorization() async throws -> EnsureAuthorizationResult {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationState = map(settings.authorizationStatus)
            return .authorized
        case .denied:
            authorizationState = .denied
            return .denied
        case .notDetermined:
            let granted = try await center.requestAuthorization()
            await refreshAuthorizationStatus()
            return granted ? .authorized : .denied
        case .unknown:
            await refreshAuthorizationStatus()
            return .unavailable
        }
    }

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        try await ensureAuthorization() == .authorized
    }

    func loadPreferences() -> NotificationPreferences {
        preferencesStore.load()
    }

    func savePreferences(_ preferences: NotificationPreferences) {
        preferencesStore.save(preferences)
    }

    /// Reconciles pending daily-summary notifications with the desired set. Unchanged requests are
    /// left in place, changed ones are replaced atomically, stale ones removed, and overlapping
    /// calls are serialized by `DailyNotificationScheduler` (latest request wins).
    func rescheduleDailyNotifications(
        state: SharedAppState,
        snapshots: [UUID: CachedLocationSnapshot]
    ) async {
        await refreshAuthorizationStatus()
        let preferences = preferencesStore.load()
        let desired = DailyNotificationDescriptorBuilder.descriptors(
            state: state,
            snapshots: snapshots,
            preferences: preferences,
            isAuthorized: authorizationState == .authorized || authorizationState == .provisional
        )
        let result = await dailyScheduler.apply(desired: desired)
        if !result.failedIdentifiers.isEmpty {
            logger.error("Failed to schedule \(result.failedIdentifiers.count) daily summary notification(s); existing ones were kept")
        }
    }

    func evaluateSuccessfulRefresh(
        location: SavedLocation,
        previous: CachedLocationSnapshot?,
        current: CachedLocationSnapshot,
        wasSuccessfulNetworkRefresh: Bool
    ) async {
        await refreshAuthorizationStatus()
        let preferences = preferencesStore.load()
        guard preferences.notificationsEnabled,
              authorizationState == .authorized || authorizationState == .provisional else {
            return
        }

        let ledger = ledgerStore.load()
        let candidates = QualityAlertEvaluator.candidates(
            location: location,
            snapshot: current,
            preferences: preferences,
            ledger: ledger,
            wasSuccessfulNetworkRefresh: wasSuccessfulNetworkRefresh
        )

        for candidate in candidates {
            let scheduleRequest = NotificationScheduleRequest(
                identifier: "quality.\(location.id.uuidString.lowercased()).\(candidate.key.forecastDate).\(candidate.key.eventType.rawValue).r\(candidate.key.revision)",
                title: candidate.title,
                body: candidate.body,
                userInfo: [
                    "locationID": location.id.uuidString,
                    "kind": "qualityAlert",
                ],
                playSound: preferences.playSound,
                delaySeconds: 0
            )
            do {
                try await center.add(scheduleRequest)
                ledgerStore.record(candidate.key)
            } catch {
                logger.error("Failed to schedule quality alert notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func removeNotifications(for locationID: UUID) async {
        let pending = await unCenter.pendingNotificationRequests()
        let qualityPrefix = "quality.\(locationID.uuidString.lowercased())."
        let identifiers = pending
            .map(\.identifier)
            .filter {
                DailyNotificationSchedulePlanner.dailyIdentifierBelongs(to: locationID, identifier: $0)
                    || $0.hasPrefix(qualityPrefix)
            }
        unCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        unCenter.removeDeliveredNotifications(withIdentifiers: identifiers)

        var preferences = preferencesStore.load()
        preferences.removeRule(for: locationID)
        preferencesStore.save(preferences)
    }

    func runTestNotification(
        locationName: String,
        playSound: Bool,
        onProgress: NotificationTestProgressHandler? = nil
    ) async -> NotificationTestResult {
        await NotificationTestWorkflow.run(
            center: center,
            locationName: locationName,
            playSound: playSound,
            delaySeconds: 3,
            onProgress: onProgress,
            waitForForeground: { identifier, timeout in
                await Self.waitForForegroundPresentation(identifier: identifier, timeout: timeout)
            }
        )
    }

    private static func waitForForegroundPresentation(identifier: String, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let name = NotificationTestWorkflow.foregroundPresentedNotification
            var token: NSObjectProtocol?
            let lock = NSLock()
            var resumed = false

            func finish(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                if let token {
                    NotificationCenter.default.removeObserver(token)
                }
                continuation.resume(returning: value)
            }

            token = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { note in
                guard let presentedID = note.userInfo?["identifier"] as? String,
                      presentedID == identifier else { return }
                finish(true)
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                finish(false)
            }
        }
    }

    private func map(_ status: NotificationSettingsSnapshot.AuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        case .unknown: return .notDetermined
        }
    }
}

/// `UNUserNotificationCenter` adapter for daily summaries.
struct UNDailyNotificationScheduling: DailyNotificationScheduling, @unchecked Sendable {
    let center: UNUserNotificationCenter

    func pendingDailyDescriptors() async -> [DailyNotificationDescriptor] {
        await center.pendingNotificationRequests()
            .filter { DailyNotificationSchedulePlanner.isDailyIdentifier($0.identifier) }
            .map { request in
                let components = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
                let locationID = (request.content.userInfo["locationID"] as? String).flatMap(UUID.init(uuidString:))
                    ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                return DailyNotificationDescriptor(
                    identifier: request.identifier,
                    locationID: locationID,
                    title: request.content.title,
                    body: request.content.body,
                    playSound: request.content.sound != nil,
                    year: components?.year ?? 0,
                    month: components?.month ?? 0,
                    day: components?.day ?? 0,
                    hour: components?.hour ?? 0,
                    minute: components?.minute ?? 0,
                    timeZoneIdentifier: components?.timeZone?.identifier ?? ""
                )
            }
    }

    func schedule(_ descriptor: DailyNotificationDescriptor) async throws {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.body = descriptor.body
        content.userInfo = [
            "locationID": descriptor.locationID.uuidString,
            "kind": "dailySummary",
        ]
        if descriptor.playSound { content.sound = .default }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: descriptor.timeZoneIdentifier)
        components.year = descriptor.year
        components.month = descriptor.month
        components.day = descriptor.day
        components.hour = descriptor.hour
        components.minute = descriptor.minute
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        // Same identifier replaces the existing pending request in place.
        try await center.add(UNNotificationRequest(identifier: descriptor.identifier, content: content, trigger: trigger))
    }

    func removePending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
