import AppKit
import Foundation

/// Keeps widget deep links from spawning a second SunsetHue process when one
/// is already running (common when both Xcode DerivedData and /Applications exist).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Local notification: `object` is a `URL`.
    static let localOpenURLNotification = Notification.Name("com.andrewtryder.SunsetHue.localOpenURL")
    private static let forwardedOpenURLNotification = Notification.Name("com.andrewtryder.SunsetHue.forwardedOpenURL")

    private var isSecondaryInstance = false

    func applicationWillFinishLaunching(_ notification: Notification) {
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
        guard isSecondaryInstance else { return }
        activateExistingInstance()
        NSApp.terminate(nil)
    }

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

    @objc private func handleForwardedURL(_ notification: Notification) {
        guard let string = notification.userInfo?["url"] as? String,
              let url = URL(string: string) else { return }
        NotificationCenter.default.post(name: Self.localOpenURLNotification, object: url)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func activateExistingInstance() {
        let current = NSRunningApplication.current
        guard let existing = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).first(where: { $0 != current }) else { return }
        existing.activate(options: [.activateAllWindows])
    }
}
