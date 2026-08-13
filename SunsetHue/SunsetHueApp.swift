import SwiftUI
import AppKit
import SunsetHueCore

@main
struct SunsetHueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @StateObject private var menuBarPreferencesStore = MenuBarPreferencesStore()
    @StateObject private var menuBarLabelController = MenuBarLabelController()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("menuBarOnlyMode") private var menuBarOnlyMode = false
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
                    menuBarLabelController.attach(appModel: appModel, preferencesStore: menuBarPreferencesStore)
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
                SettingsLink()
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

        // Compact monochrome status-item label is separate from the richer `.window` popup.
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            SunsetHueMenuBarPopoverView(
                preferencesStore: menuBarPreferencesStore,
                labelController: menuBarLabelController
            )
            .environmentObject(appModel)
        } label: {
            SunsetHueMenuBarLabel(labelController: menuBarLabelController)
                .onAppear {
                    menuBarLabelController.attach(appModel: appModel, preferencesStore: menuBarPreferencesStore)
                }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: showMenuBarExtra) { _, isInserted in
            guard !isInserted, menuBarOnlyMode else { return }
            menuBarOnlyMode = false
            AppPreferenceDefaults.shared.openMainWindowOnLaunch = true
            AppPresentationModeController.apply(menuBarOnly: false)
            MainWindowPresenter.present(openWindow: openWindow)
        }

        Settings {
            SunsetHueSettingsView(
                menuBarPreferencesStore: menuBarPreferencesStore,
                menuBarLabelController: menuBarLabelController
            )
            .environmentObject(appModel)
        }
    }
}

@MainActor
enum MainWindowPresenter {
    static func present(openWindow: OpenWindowAction) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "SunsetHue" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
