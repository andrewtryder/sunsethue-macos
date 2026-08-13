import AppKit
import Foundation
import UserNotifications
import SunsetHueCore

/// Keeps widget deep links from spawning a second SunsetHue process when one
/// is already running (common when both Xcode DerivedData and /Applications exist).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Local notification: `object` is a `URL`.
    static let localOpenURLNotification = Notification.Name("com.andrewtryder.SunsetHue.localOpenURL")
    private static let forwardedOpenURLNotification = Notification.Name("com.andrewtryder.SunsetHue.forwardedOpenURL")

    private var isSecondaryInstance = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleForwardedURL(_:)),
            name: Self.forwardedOpenURLNotification,
            object: Bundle.main.bundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )

        let current = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { $0 != current }
        isSecondaryInstance = !others.isEmpty
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menuBarOnly = UserDefaults.standard.bool(forKey: "menuBarOnlyMode")
        AppPresentationModeController.apply(menuBarOnly: menuBarOnly)

        guard isSecondaryInstance else { return }
        activateExistingInstance()
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: Self.reopenMainWindowNotification, object: nil)
        }
        return true
    }

    /// Posted when the Dock icon is clicked and no windows are visible.
    static let reopenMainWindowNotification = Notification.Name("com.andrewtryder.SunsetHue.reopenMainWindow")

    func application(_ application: NSApplication, open urls: [URL]) {
        if isSecondaryInstance {
            for url in urls {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.forwardedOpenURLNotification,
                    object: Bundle.main.bundleIdentifier,
                    userInfo: ["url": url.absoluteString],
                    deliverImmediately: true
                )
            }
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }

        for url in urls {
            NotificationCenter.default.post(name: Self.localOpenURLNotification, object: url)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        NotificationCenter.default.post(
            name: NotificationTestWorkflow.foregroundPresentedNotification,
            object: nil,
            userInfo: ["identifier": identifier]
        )

        var options: UNNotificationPresentationOptions = [.banner, .list]
        if Self.playSoundPreferenceEnabled() {
            options.insert(.sound)
        }
        return options
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Test notifications (and any request without a location) must not deep-link.
        guard
            let value = response.notification.request.content.userInfo["locationID"] as? String,
            let id = UUID(uuidString: value)
        else {
            return
        }

        let url = DeepLink.locationURL(id: id)
        NotificationCenter.default.post(name: Self.localOpenURLNotification, object: url)
        NotificationCenter.default.post(name: Self.reopenMainWindowNotification, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc @MainActor private func handleForwardedURL(_ notification: Notification) {
        guard let string = notification.userInfo?["url"] as? String,
              let url = URL(string: string) else { return }
        NotificationCenter.default.post(name: Self.localOpenURLNotification, object: url)
        NotificationCenter.default.post(name: Self.reopenMainWindowNotification, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func activateExistingInstance() {
        let current = NSRunningApplication.current
        guard let existing = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).first(where: { $0 != current }) else { return }
        existing.activate(options: [.activateAllWindows])
    }

    private static func playSoundPreferenceEnabled() -> Bool {
        let store = NotificationPreferencesStore()
        return store.load().playSound
    }
}
