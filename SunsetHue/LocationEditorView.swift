import SwiftUI
import CoreLocation
import MapKit
import SunsetHueCore

struct LocationEditorView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    var locationProvider: any CurrentLocationProviding = CoreCurrentLocationProvider()
    @StateObject private var placeSearch = PlaceSearchController()
    @State private var statusMessage: String?
    @State private var isLocating = false
    @State private var showTimeZonePicker = false
    @State private var showAdvanced = false

    private var draft: Binding<LocationEditorDraft> {
        $appModel.editorDraft
    }

    private var hasSelectedCoordinates: Bool {
        Double(appModel.editorDraft.latitude.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && Double(appModel.editorDraft.longitude.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    TextField(
                        "Search places",
                        text: Binding(
                            get: { placeSearch.query },
                            set: { placeSearch.updateQuery($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .help("Search for a city or place. Selecting a result fills name, coordinates, and time zone when available.")

                    if !placeSearch.results.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(placeSearch.results.enumerated()), id: \.offset) { _, completion in
                                    Button {
                                        Task { await selectPlace(completion) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(completion.title)
                                                .foregroundStyle(.primary)
                                            if !completion.subtitle.isEmpty {
                                                Text(completion.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(placeSearch.isResolving || isLocating)
                                }
                            }
                        }
                        .frame(maxHeight: 160)
                    }

                    if hasSelectedCoordinates {
                        selectedPlaceSummary
                    }

                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        Label("Use Current Location", systemImage: "location.fill")
                    }
                    .disabled(isLocating || placeSearch.isResolving)

                    if isLocating || placeSearch.isResolving {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let message = statusMessage ?? placeSearch.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(message)
                    }
                }

                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("Display Name", text: draft.name)
                    TextField("Latitude", text: draft.latitude)
                    TextField("Longitude", text: draft.longitude)

                    Button {
                        showTimeZonePicker = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Time Zone")
                                    .foregroundStyle(.primary)
                                Text(TimeZoneCatalog.friendlyCity(for: appModel.editorDraft.timeZoneIdentifier))
                                    .font(.body.weight(.medium))
                                Text(appModel.editorDraft.timeZoneIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Choose an IANA time zone for this location.")
                }

                Section("Forecast Options") {
                    Picker("Forecast Days", selection: draft.forecastDays) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
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
            .sheet(isPresented: $showTimeZonePicker) {
                TimeZonePickerView(selection: draft.timeZoneIdentifier)
            }
            .onAppear {
                showAdvanced = appModel.isEditingExisting
                if !appModel.editorDraft.name.isEmpty {
                    placeSearch.syncToSelectedName(appModel.editorDraft.name)
                }
            }
        }
        .padding()
        .accessibilityLabel(appModel.isEditingExisting ? "Edit location" : "Add location")
    }

    private var selectedPlaceSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appModel.editorDraft.name.isEmpty ? "Selected Place" : appModel.editorDraft.name)
                .font(.body.weight(.semibold))
            Text(coordinateSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(timeZoneSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var coordinateSummary: String {
        let lat = appModel.editorDraft.latitude
        let lon = appModel.editorDraft.longitude
        return "\(lat), \(lon)"
    }

    private var timeZoneSummary: String {
        let identifier = appModel.editorDraft.timeZoneIdentifier
        return "\(TimeZoneCatalog.friendlyCity(for: identifier)) · \(identifier)"
    }

    private func selectPlace(_ completion: MKLocalSearchCompletion) async {
        statusMessage = nil
        do {
            let place = try await placeSearch.resolve(completion)
            var fields = LocationDraftPlaceFields(
                name: appModel.editorDraft.name,
                latitude: appModel.editorDraft.latitude,
                longitude: appModel.editorDraft.longitude,
                timeZoneIdentifier: appModel.editorDraft.timeZoneIdentifier
            )
            fields.apply(place)
            appModel.editorDraft.name = fields.name
            appModel.editorDraft.latitude = fields.latitude
            appModel.editorDraft.longitude = fields.longitude
            appModel.editorDraft.timeZoneIdentifier = fields.timeZoneIdentifier
            placeSearch.syncToSelectedName(fields.name)
            statusMessage = nil
        } catch {
            // All-or-nothing: draft fields are only mutated after successful resolve.
            statusMessage = error.localizedDescription
        }
    }

    private func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        do {
            let result = try await locationProvider.requestLocation()
            appModel.editorDraft.latitude = String(format: "%.5f", result.latitude)
            appModel.editorDraft.longitude = String(format: "%.5f", result.longitude)
            if let timeZoneIdentifier = result.timeZoneIdentifier {
                appModel.editorDraft.timeZoneIdentifier = timeZoneIdentifier
            }
            if appModel.editorDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appModel.editorDraft.name = "Current Location"
            }
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
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
            let timeZoneIdentifier = await GeographicTimeZoneResolver.timeZoneIdentifier(for: location)
            resumeOnce(
                returning: CurrentLocationResult(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timeZoneIdentifier: timeZoneIdentifier
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
