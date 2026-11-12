import SwiftUI
import SunsetHueCore

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationSplitView {
            LocationSidebar()
        } detail: {
            if let location = appModel.selectedLocation {
                ForecastDetailView(location: location)
            } else {
                EmptyLocationsView()
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .sheet(isPresented: $appModel.isPresentingEditor) {
            LocationEditorView()
                .environmentObject(appModel)
                .frame(minWidth: 480, minHeight: 640)
        }
        .overlay(alignment: .bottom) {
            if let message = appModel.bannerMessage {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding()
                    .accessibilityLabel(message)
            }
        }
    }
}

struct EmptyLocationsView: View {
    @EnvironmentObject private var appModel: AppModel

    private var hasKey: Bool { appModel.credentialState == .configured }
    private var hasLocation: Bool { !appModel.state.locations.isEmpty }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange, .yellow)
            Text("Welcome to SunsetHue")
                .font(.largeTitle.weight(.semibold))
            Text("Three quick steps to see your first forecast.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                SetupStepRow(
                    number: 1,
                    title: "Add your API key",
                    detail: appModel.credentialState == .unavailable
                        ? "The Keychain is locked or unavailable. Unlock your Mac, then try again."
                        : "Get a key at sunsethue.com/dev-api, then paste it in Settings → Account. It is stored only in your Keychain.",
                    isDone: hasKey
                ) {
                    SettingsLink { Text("Open Settings…") }
                }
                SetupStepRow(
                    number: 2,
                    title: "Add a location",
                    detail: "Search for a place or enter coordinates.",
                    isDone: hasLocation
                ) {
                    Button("Add Location…") { appModel.beginAddLocation() }
                        .buttonStyle(.borderedProminent)
                }
                SetupStepRow(
                    number: 3,
                    title: "Test the connection",
                    detail: "Use Test Connection in Settings → Account. "
                        + "\"Authentication failed\" means the key was rejected; "
                        + "\"Network unavailable\" or a timeout is temporary and retries automatically.",
                    isDone: false
                ) {
                    SettingsLink { Text("Test Connection…") }
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtmosphereBackground())
    }
}

private struct SetupStepRow<Action: View>: View {
    let number: Int
    let title: String
    let detail: String
    let isDone: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(isDone ? Color.green : Color.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if !isDone { action().padding(.top, 2) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(isDone ? "Done." : detail)")
    }
}

#Preview("Empty") {
    ContentView()
        .environmentObject(AppModel(
            settingsStore: InMemorySettingsStore(),
            forecastCache: InMemoryForecastCache(),
            credentialStore: InMemoryCredentialStore()
        ))
}
