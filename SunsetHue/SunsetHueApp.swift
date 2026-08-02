import SwiftUI
import SunsetHueCore

@main
struct SunsetHueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
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
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    appModel.applicationDidBecomeActive()
                }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .commands {
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
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }

        MenuBarExtra(
            "SunsetHue",
            systemImage: "sun.horizon",
            isInserted: $showMenuBarExtra
        ) {
            SunsetHueMenuBarView()
                .environmentObject(appModel)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SunsetHueSettingsView()
                .environmentObject(appModel)
        }
    }
}
