import SwiftUI
import AppKit
import SunsetHueCore

struct SunsetHueMenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if appModel.state.locations.isEmpty {
            Text("No locations yet")
            Button("Open SunsetHue") {
                MainWindowPresenter.present(openWindow: openWindow)
            }
        } else {
            ForEach(appModel.menuBarLocationRows) { row in
                Button {
                    appModel.selectLocation(id: row.id)
                    MainWindowPresenter.present(openWindow: openWindow)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                        Text(row.detail)
                            .sunsetHueMuted()
                    }
                }
            }
            if let status = appModel.menuBarRefreshStatusLine {
                Text(status)
                    .sunsetHueMuted()
            }
            Divider()
            Button("Refresh All") {
                appModel.refreshAllFromCommand()
            }
            .keyboardShortcut("r", modifiers: [.command])
            Button("Open SunsetHue…") {
                MainWindowPresenter.present(openWindow: openWindow)
            }
        }

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()
        Button("Quit SunsetHue") {
            NSApp.terminate(nil)
        }
    }
}

enum SettingsPresenter {
    @MainActor
    static func present(openSettings: OpenSettingsAction) {
        NSApp.activate(ignoringOtherApps: true)
        // Defer one run-loop turn so MenuBarExtra can dismiss before the Settings window appears.
        DispatchQueue.main.async {
            openSettings()
        }
    }
}
