import AppKit

@MainActor
enum AppPresentationModeController {
    static func apply(menuBarOnly: Bool) {
        let policy: NSApplication.ActivationPolicy = menuBarOnly ? .accessory : .regular
        _ = NSApp.setActivationPolicy(policy)
        if !menuBarOnly {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
