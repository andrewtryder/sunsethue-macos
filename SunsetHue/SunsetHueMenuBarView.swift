import SwiftUI
import SunsetHueCore

struct SunsetHueMenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let location = appModel.selectedLocation {
            Text(location.name)
            if let snapshot = appModel.snapshot {
                Text(statusText(for: snapshot))
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Open SunsetHue") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Refresh") {
                appModel.refreshSelectedFromCommand()
            }
            .keyboardShortcut("r", modifiers: [.command])
            Button("Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        } else {
            Text("No locations yet")
            Button("Open SunsetHue") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        Divider()
        Button("Quit SunsetHue") {
            NSApp.terminate(nil)
        }
    }

    private func statusText(for snapshot: CachedLocationSnapshot) -> String {
        switch snapshot.status {
        case .current:
            return "Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"
        case .stale:
            return "Stale — open app to refresh"
        case .authenticationRequired:
            return "API key needed"
        case .rateLimited:
            return "Rate limited"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        }
    }
}
