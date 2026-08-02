import SwiftUI
import SunsetHueCore

@main
struct SunsetHueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
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
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Location…") {
                    appModel.beginAddLocation()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}
