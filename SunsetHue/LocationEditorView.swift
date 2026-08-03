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
                    TextField("System time zone (IANA)", text: draft.timeZoneIdentifier)
                        .help("Uses this Mac’s current time zone when filled from Current Location — not inferred from coordinates. Example: America/New_York")
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
                    if isLocating {
                        ProgressView()
                            .controlSize(.small)
                    }
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
    private var timeoutTask: Task<Void, Never>?
    private let timeoutSeconds: TimeInterval = 20

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() async throws -> CurrentLocationResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CurrentLocationResult, Error>) in
                if self.continuation != nil {
                    continuation.resume(throwing: LocationProviderError.busy)
                    return
                }
                self.continuation = continuation
                self.startTimeout()
                self.beginAuthorizationOrRequest()
            }
        } onCancel: {
            Task { @MainActor in
                self.resumeOnce(throwing: CancellationError())
            }
        }
    }

    private func beginAuthorizationOrRequest() {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            resumeOnce(throwing: LocationProviderError.denied)
        default:
            // macOS may report authorized / when-in-use via higher raw values.
            if manager.authorizationStatus.rawValue > 2 {
                manager.requestLocation()
            } else {
                resumeOnce(throwing: LocationProviderError.unavailable)
            }
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            resumeOnce(throwing: LocationProviderError.timeout)
        }
    }

    private func resumeOnce(returning result: CurrentLocationResult) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }

    private func resumeOnce(throwing error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard continuation != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                resumeOnce(throwing: LocationProviderError.denied)
            case .notDetermined:
                break
            default:
                if manager.authorizationStatus.rawValue > 2 {
                    manager.requestLocation()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                resumeOnce(throwing: LocationProviderError.unavailable)
                return
            }
            // System time zone of this Mac — not geographically inferred from coordinates.
            resumeOnce(
                returning: CurrentLocationResult(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timeZoneIdentifier: TimeZone.current.identifier
                )
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            resumeOnce(throwing: LocationProviderError.unavailable)
        }
    }
}

enum LocationProviderError: LocalizedError {
    case denied
    case unavailable
    case busy
    case timeout

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Location access denied. Enter coordinates manually."
        case .unavailable:
            return "Could not determine current location. Enter coordinates manually."
        case .busy:
            return "A location request is already in progress."
        case .timeout:
            return "Timed out waiting for location. Enter coordinates manually."
        }
    }
}
