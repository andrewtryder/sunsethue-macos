import Foundation
import UserNotifications
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

    enum TestNotificationError: LocalizedError, Sendable {
        case notAuthorized
        case alertsDisabled
        case schedulingFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Notifications are not allowed. Enable them in System Settings."
            case .alertsDisabled:
                return "SunsetHue is allowed, but alerts are turned off in System Settings."
            case .schedulingFailed(let message):
                return message
            }
        }
    }

    private let center: UNUserNotificationCenter
    private let preferencesStore: any NotificationPreferencesStoring
    private let ledgerStore: NotificationDeliveryLedgerStore

    private(set) var authorizationState: AuthorizationState = .notDetermined

    init(
        center: UNUserNotificationCenter = .current(),
        preferencesStore: any NotificationPreferencesStoring = NotificationPreferencesStore(),
        ledgerStore: NotificationDeliveryLedgerStore = NotificationDeliveryLedgerStore()
    ) {
        self.center = center
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
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted ? .authorized : .denied
        @unknown default:
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
            try? await center.add(request)
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
            let content = UNMutableNotificationContent()
            content.title = candidate.title
            content.body = candidate.body
            content.userInfo = [
                "locationID": location.id.uuidString,
                "kind": "qualityAlert",
            ]
            if preferences.playSound {
                content.sound = .default
            }
            let request = UNNotificationRequest(
                identifier: "quality.\(location.id.uuidString.lowercased()).\(candidate.key.forecastDate).\(candidate.key.eventType.rawValue).r\(candidate.key.revision)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
            ledgerStore.record(candidate.key)
        }
    }

    func removeNotifications(for locationID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let qualityPrefix = "quality.\(locationID.uuidString.lowercased())."
        let identifiers = pending
            .map(\.identifier)
            .filter {
                DailyNotificationSchedulePlanner.dailyIdentifierBelongs(to: locationID, identifier: $0)
                    || $0.hasPrefix(qualityPrefix)
            }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)

        var preferences = preferencesStore.load()
        if preferences.locationID == locationID {
            preferences.locationID = nil
            preferencesStore.save(preferences)
        }
    }

    func sendTestNotification(locationName: String, playSound: Bool) async throws {
        let auth = try await ensureAuthorization()
        guard auth == .authorized else {
            throw TestNotificationError.notAuthorized
        }

        let settings = await center.notificationSettings()
        if settings.alertSetting == .disabled {
            throw TestNotificationError.alertsDisabled
        }

        let content = UNMutableNotificationContent()
        content.title = "SunsetHue test notification"
        content.body = "This is a test for \(locationName). Forecast alerts use the same local notification system."
        content.userInfo = ["kind": "test"]
        if playSound {
            content.sound = .default
        }

        // Slight delay is more reliable than a nil trigger while Settings is frontmost on macOS.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "test.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            throw TestNotificationError.schedulingFailed(error.localizedDescription)
        }
    }

    private func removePendingDailyRequests() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter(DailyNotificationSchedulePlanner.isDailyIdentifier)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func map(_ status: UNAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .notDetermined
        }
    }
}
