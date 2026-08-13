import Foundation
import UserNotifications
import SunsetHueCore

struct SystemNotificationCenterClient: NotificationCenterClienting {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

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
        let trigger: UNNotificationTrigger?
        if request.delaySeconds > 0 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: request.delaySeconds, repeats: false)
        } else {
            trigger = nil
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
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    private func mapSetting(_ setting: UNNotificationSetting) -> NotificationSettingsSnapshot.Setting {
        switch setting {
        case .enabled: return .enabled
        case .disabled: return .disabled
        case .notSupported: return .notSupported
        @unknown default: return .unknown
        }
    }
}
