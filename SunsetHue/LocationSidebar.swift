import SwiftUI

struct LocationSidebar: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(selection: Binding(
            get: { appModel.selectedLocationID },
            set: { if let id = $0 { appModel.selectLocation(id: id) } }
        )) {
            Section("Locations") {
                ForEach(appModel.state.locations) { location in
                    Text(location.name)
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
            Button {
                appModel.beginAddLocation()
            } label: {
                Label("Add Location", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Add Location")
            .accessibilityLabel("Add Location")
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
