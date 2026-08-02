import SwiftUI
import CoreLocation
import SunsetHueCore

struct LocationEditorView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationProvider = CurrentLocationProvider()
    @State private var testMessage: String?
    @State private var isTesting = false

    private var draft: Binding<LocationEditorDraft> {
        $appModel.editorDraft
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    TextField("Display Name", text: draft.name)
                    TextField("Latitude", text: draft.latitude)
                    TextField("Longitude", text: draft.longitude)
                    TextField("IANA Time Zone", text: draft.timeZoneIdentifier)
                        .help("Example: America/New_York")
                    Button("Use Current Location") {
                        locationProvider.request {
                            if let coordinate = locationProvider.coordinate {
                                appModel.editorDraft.latitude = String(format: "%.5f", coordinate.latitude)
                                appModel.editorDraft.longitude = String(format: "%.5f", coordinate.longitude)
                                if let tz = locationProvider.timeZoneIdentifier {
                                    appModel.editorDraft.timeZoneIdentifier = tz
                                }
                            }
                            if let error = locationProvider.errorMessage {
                                testMessage = error
                            }
                        }
                    }
                    if let locationError = locationProvider.errorMessage {
                        Text(locationError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Credentials") {
                    SecureField("SunsetHue API Key", text: draft.apiKey)
                    Text("Stored only in the Keychain (shared with the widget). Never written to disk files or logs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Forecast Options") {
                    Stepper(value: draft.forecastDays, in: 1...3) {
                        Text("Forecast Days: \(appModel.editorDraft.forecastDays)")
                    }
                    Toggle("Include Sunrise", isOn: draft.includeSunrise)
                    Toggle("Include Sunset", isOn: draft.includeSunset)
                    Picker("Refresh Interval", selection: draft.refreshIntervalHours) {
                        Text("6 hours").tag(6)
                        Text("12 hours").tag(12)
                        Text("24 hours").tag(24)
                    }
                }

                Section {
                    Button {
                        Task {
                            isTesting = true
                            testMessage = await appModel.testConnection(draft: appModel.editorDraft)
                            isTesting = false
                        }
                    } label: {
                        if isTesting {
                            ProgressView()
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTesting)

                    if let testMessage {
                        Text(testMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(testMessage)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(appModel.isEditingExisting ? "Edit Location" : "Add Location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await appModel.saveEditor() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
    }
}

@MainActor
final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var timeZoneIdentifier: String?
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request(completion: @escaping () -> Void) {
        self.completion = completion
        errorMessage = nil
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = "Location access denied. Enter coordinates manually."
            completion()
        default:
            // macOS may report authorized-when-in-use equivalents via raw values.
            if manager.authorizationStatus.rawValue > 0 {
                manager.requestLocation()
            } else {
                errorMessage = "Unable to access location. Enter coordinates manually."
                completion()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus.rawValue > 2 {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            coordinate = location.coordinate
            timeZoneIdentifier = TimeZone.current.identifier
            completion?()
            completion = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = "Could not determine current location. Enter coordinates manually."
            completion?()
            completion = nil
        }
    }
}
