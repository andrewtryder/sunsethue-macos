import SwiftUI
import AppKit
import SunsetHueCore

@main
struct SunsetHueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        // Single unique window — openWindow(id:) brings it forward instead of spawning copies.
        Window("SunsetHue", id: "main") {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 880, minHeight: 560)
                .onOpenURL { url in
                    appModel.handle(url: url)
                }
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.localOpenURLNotification)) { note in
                    if let url = note.object as? URL {
                        appModel.handle(url: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.reopenMainWindowNotification)) { _ in
                    MainWindowPresenter.present(openWindow: openWindow)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    appModel.applicationDidBecomeActive()
                }
                .onAppear {
                    if !AppPreferenceDefaults.shared.openMainWindowOnLaunch {
                        DispatchQueue.main.async {
                            if let window = NSApp.windows.first(where: {
                                $0.identifier?.rawValue == "main" || $0.title == "SunsetHue"
                            }) {
                                window.close()
                            }
                        }
                    }
                }
        }
        .defaultLaunchBehavior(
            AppPreferenceDefaults.shared.openMainWindowOnLaunch ? .presented : .suppressed
        )
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsPresenter.present(openSettings: openSettings)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Location…") {
                    appModel.beginAddLocation()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Location") {
                Button("Refresh Selected Location") {
                    appModel.refreshSelectedFromCommand()
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("Edit Selected Location…") {
                    appModel.editSelectedLocation()
                }
                .keyboardShortcut("e", modifiers: [.command])
                Divider()
                Button("Previous Location") {
                    appModel.selectPreviousLocation()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .command])
                Button("Next Location") {
                    appModel.selectNextLocation()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .command])
                Divider()
                ForEach(Array(appModel.state.locations.prefix(9).enumerated()), id: \.element.id) { index, location in
                    Button(location.name) {
                        appModel.selectLocation(at: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }
            }
            CommandGroup(after: .windowList) {
                Button("Open Main Window") {
                    MainWindowPresenter.present(openWindow: openWindow)
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            SunsetHueMenuBarView()
                .environmentObject(appModel)
        } label: {
            Label(appModel.menuBarStatusText, systemImage: "sun.horizon")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SunsetHueSettingsView()
                .environmentObject(appModel)
        }
    }
}

enum MainWindowPresenter {
    static func present(openWindow: OpenWindowAction) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        // Ensure an already-open main window is ordered front (not buried under Settings).
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "SunsetHue" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
