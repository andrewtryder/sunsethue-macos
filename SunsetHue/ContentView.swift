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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange, .yellow)
            Text("Welcome to SunsetHue")
                .font(.largeTitle.weight(.semibold))
            Text("Add a location, then set your API key in Settings → Account.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Add Location…") {
                appModel.beginAddLocation()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtmosphereBackground())
        .accessibilityElement(children: .combine)
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
