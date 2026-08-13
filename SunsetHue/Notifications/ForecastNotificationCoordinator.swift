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

    func rescheduleDailyNotifications(
        state: SharedAppState,
        snapshots: [UUID: CachedLocationSnapshot]
    ) async {
        await refreshAuthorizationStatus()
        let preferences = preferencesStore.load()
        await removePendingDailyRequests()

        guard preferences.notificationsEnabled,
              preferences.dailySummary.enabled,
              authorizationState == .authorized || authorizationState == .provisional,
              let locationID = preferences.locationID,
              let location = state.locations.first(where: { $0.id == locationID }),
              let snapshot = snapshots[locationID],
              let bundle = snapshot.bundle,
              let timeZone = location.timeZone else {
            return
        }

        let plans = DailyNotificationSchedulePlanner.plans(
            location: location,
            rule: preferences.dailySummary,
            now: Date(),
            dayCount: max(2, location.forecastDays)
        )

        for plan in plans {
            guard let contentDraft = DailySummaryContentBuilder.content(
                location: location,
                bundle: bundle,
                deliveryDate: plan.deliveryDate
            ) else { continue }

            let content = UNMutableNotificationContent()
            content.title = contentDraft.title
            content.body = contentDraft.body
            content.userInfo = [
                "locationID": location.id.uuidString,
                "kind": "dailySummary",
            ]
            if preferences.playSound {
                content.sound = .default
            }

            let components = DailyNotificationSchedulePlanner.dateComponents(
                for: plan,
                timeZone: timeZone
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: plan.identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await unCenter.add(request)
            } catch {
                logger.error("Failed to schedule daily summary notification: \(error.localizedDescription, privacy: .public)")
            }
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
        if preferences.locationID == locationID {
            preferences.locationID = nil
            preferencesStore.save(preferences)
        }
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

    private func removePendingDailyRequests() async {
        let pending = await unCenter.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter(DailyNotificationSchedulePlanner.isDailyIdentifier)
        unCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
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
