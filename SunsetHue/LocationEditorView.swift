import SwiftUI
import CoreLocation
import SunsetHueCore

struct LocationEditorView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    var locationProvider: any CurrentLocationProviding = CoreCurrentLocationProvider()
    @State private var statusMessage: String?
    @State private var isLocating = false

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
                        Task {
                            isLocating = true
                            defer { isLocating = false }
                            do {
                                let result = try await locationProvider.requestLocation()
                                appModel.editorDraft.latitude = String(format: "%.5f", result.latitude)
                                appModel.editorDraft.longitude = String(format: "%.5f", result.longitude)
                                appModel.editorDraft.timeZoneIdentifier = result.timeZoneIdentifier
                                statusMessage = nil
                            } catch {
                                statusMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(isLocating)
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(statusMessage)
                    }
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
        .accessibilityLabel(appModel.isEditingExisting ? "Edit location" : "Add location")
    }
}

@MainActor
final class CoreCurrentLocationProvider: NSObject, ObservableObject, CurrentLocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CurrentLocationResult, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() async throws -> CurrentLocationResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .authorizedAlways:
                manager.requestLocation()
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                continuation.resume(throwing: LocationProviderError.denied)
                self.continuation = nil
            default:
                if manager.authorizationStatus.rawValue > 0 {
                    manager.requestLocation()
                } else {
                    continuation.resume(throwing: LocationProviderError.unavailable)
                    self.continuation = nil
                }
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
            continuation?.resume(
                returning: CurrentLocationResult(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timeZoneIdentifier: TimeZone.current.identifier
                )
            )
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: LocationProviderError.unavailable)
            continuation = nil
        }
    }
}

enum LocationProviderError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Location access denied. Enter coordinates manually."
        case .unavailable:
            return "Could not determine current location. Enter coordinates manually."
        }
    }
}
