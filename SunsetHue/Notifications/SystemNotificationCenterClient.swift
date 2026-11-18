import Foundation
import SunsetHueCore

// `@preconcurrency` only suppresses Sendable warnings on Apple SDK async ObjC return types
// (`UNNotificationSettings`, `UNNotificationRequest`, `UNNotification`) whose contents are mapped
// immediately to Sendable value types before returning.
@preconcurrency import UserNotifications

/// Stateless adapter over `UNUserNotificationCenter.current()`.
/// Computing `.current()` avoids storing a non-Sendable `UNUserNotificationCenter` reference;
/// `UNUserNotificationCenter.current()` is safe to call across concurrency domains.
struct SystemNotificationCenterClient: NotificationCenterClienting {
    private var center: UNUserNotificationCenter {
        .current()
    }

    init() {}

    func notificationSettings() async -> NotificationSettingsSnapshot {
        let settings = await center.notificationSettings()
        return NotificationSettingsSnapshot(
            authorizationStatus: mapAuth(settings.authorizationStatus),
            alertSetting: mapSetting(settings.alertSetting),
            notificationCenterSetting: mapSetting(settings.notificationCenterSetting),
            soundSetting: mapSetting(settings.soundSetting),
            lockScreenSetting: mapSetting(settings.lockScreenSetting)
        )
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func add(_ request: NotificationScheduleRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.userInfo = request.userInfo
        if request.playSound {
            content.sound = .default
        }
        let trigger: UNNotificationTrigger? = if request.delaySeconds > 0 {
            UNTimeIntervalNotificationTrigger(timeInterval: request.delaySeconds, repeats: false)
        } else {
            nil
        }
        let unRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(unRequest)
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func deliveredIdentifiers() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }

    func removePending(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(withIdentifiers identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func mapAuth(_ status: UNAuthorizationStatus) -> NotificationSettingsSnapshot.AuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .unknown
        }
    }

    private func mapSetting(_ setting: UNNotificationSetting) -> NotificationSettingsSnapshot.Setting {
        switch setting {
        case .enabled: .enabled
        case .disabled: .disabled
        case .notSupported: .notSupported
        @unknown default: .unknown
        }
    }
}
