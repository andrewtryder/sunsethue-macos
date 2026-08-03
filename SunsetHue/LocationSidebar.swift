import SwiftUI
import SunsetHueCore

struct LocationSidebar: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(selection: Binding(
            get: { appModel.selectedLocationID },
            set: { if let id = $0 { appModel.selectLocation(id: id) } }
        )) {
            Section("Locations") {
                ForEach(appModel.state.locations) { location in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.name)
                            .font(.headline)
                        Text(location.timeZoneIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(location.id)
                    .contextMenu {
                        Button("Edit…") { appModel.beginEditLocation(location) }
                        Button("Delete", role: .destructive) { appModel.deleteLocation(location) }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        appModel.deleteLocation(appModel.state.locations[index])
                    }
                }
            }

            if appModel.lastErrorIsAuthentication || appModel.credentialState == .missing || appModel.credentialState == .unavailable {
                Section {
                    Label(
                        appModel.lastErrorMessage ?? "Add an API key to enable forecasts.",
                        systemImage: "key.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Authentication warning")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SunsetHue")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SunsetHueConstants.marketingVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("App version")
                Spacer(minLength: 0)
                Button {
                    appModel.beginAddLocation()
                } label: {
                    Label("Add Location", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Location")
                .accessibilityLabel("Add Location")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
