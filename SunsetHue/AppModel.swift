import Foundation
import SwiftUI
import WidgetKit
import SunsetHueCore
import os

@MainActor
final class AppModel: ObservableObject {
    @Published var state: SharedAppState
    @Published var selectedLocationID: UUID?
    @Published var bundle: LocationForecastBundle?
    @Published var isRefreshing = false
    @Published var bannerMessage: String?
    @Published var isPresentingEditor = false
    @Published var editorDraft: LocationEditorDraft = .empty
    @Published var isEditingExisting = false

    private let settingsStore: SharedSettingsStore
    private let forecastCache: ForecastCache
    private let credentialStore: CredentialStore
    private let forecastService: ForecastService
    private let logger = Logger(subsystem: "com.andrewtryder.SunsetHue", category: "App")

    init(
        settingsStore: SharedSettingsStore = SharedStorageFactory.makeSettingsStore(),
        forecastCache: ForecastCache = SharedStorageFactory.makeForecastCache(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        forecastService: ForecastService = ForecastService()
    ) {
        self.settingsStore = settingsStore
        self.forecastCache = forecastCache
        self.credentialStore = credentialStore
        self.forecastService = forecastService
        self.state = (try? settingsStore.load()) ?? SharedAppState()
        self.selectedLocationID = self.state.selectedLocationID ?? self.state.locations.first?.id
        if let id = selectedLocationID {
            self.bundle = try? forecastCache.loadBundle(for: id)
        }
        // loadAPIKey migrates legacy file-keychain items once; do not rewrite on every launch.
        _ = try? credentialStore.loadAPIKey()
        // Ensure App Group migration is visible to WidgetKit immediately.
        persistState()
        reloadWidgets()
        Task { await refreshSelected(force: false) }
    }

    var selectedLocation: SavedLocation? {
        guard let selectedLocationID else { return state.locations.first }
        return state.locations.first(where: { $0.id == selectedLocationID })
    }

    var hasAPIKey: Bool {
        (try? credentialStore.loadAPIKey())?.isEmpty == false
    }

    func selectLocation(id: UUID) {
        selectedLocationID = id
        state.selectedLocationID = id
        persistState()
        bundle = try? forecastCache.loadBundle(for: id)
        Task { await refreshSelected(force: false) }
    }

    func handle(url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        switch link {
        case .location(let id):
            if state.locations.contains(where: { $0.id == id }) {
                selectLocation(id: id)
            }
        case .openApp:
            break
        }
    }

    func beginAddLocation() {
        let apiKey = (try? credentialStore.loadAPIKey()) ?? ""
        editorDraft = .empty(apiKey: apiKey)
        isEditingExisting = false
        isPresentingEditor = true
    }

    func beginEditLocation(_ location: SavedLocation) {
        let apiKey = (try? credentialStore.loadAPIKey()) ?? ""
        editorDraft = LocationEditorDraft(location: location, apiKey: apiKey)
        isEditingExisting = true
        isPresentingEditor = true
    }

    func deleteLocation(_ location: SavedLocation) {
        state.locations.removeAll { $0.id == location.id }
        if selectedLocationID == location.id {
            selectedLocationID = state.locations.first?.id
            state.selectedLocationID = selectedLocationID
            if let selectedLocationID {
                bundle = try? forecastCache.loadBundle(for: selectedLocationID)
            } else {
                bundle = nil
            }
        }
        persistState()
        reloadWidgets()
    }

    func saveEditor() async {
        do {
            let draft = editorDraft
            let trimmedKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                bannerMessage = SunsetHueError.missingCredentials.userMessage
                return
            }
            try credentialStore.saveAPIKey(trimmedKey)

            let location = try draft.makeLocation().validated(againstExisting: state.locations)
            if let index = state.locations.firstIndex(where: { $0.id == location.id }) {
                state.locations[index] = location
            } else {
                state.locations.append(location)
            }
            selectedLocationID = location.id
            state.selectedLocationID = location.id
            state.lastErrorMessage = nil
            state.lastErrorIsAuthentication = false
            persistState()
            isPresentingEditor = false
            await refreshSelected(force: true)
            reloadWidgets()
        } catch let error as SunsetHueError {
            bannerMessage = error.userMessage
        } catch {
            bannerMessage = "Unable to save location."
        }
    }

    func testConnection(draft: LocationEditorDraft) async -> String {
        do {
            let location = try draft.makeLocation().validated()
            guard let timeZone = location.timeZone else {
                return SunsetHueError.invalidLocation("Time zone identifier is invalid.").userMessage
            }
            let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return SunsetHueError.missingCredentials.userMessage }
            let client = SunsetHueClient(apiKey: key)
            let forecast = try await client.testConnection(coordinates: location.coordinates, timeZone: timeZone)
            if forecast.isQualityAvailable, let percent = PresentationFormatting.percentage(fromNormalized: forecast.quality) {
                return "Connection successful. Today's sunset quality: \(percent)."
            }
            return "Connection successful. Timing data received; model quality may be unavailable."
        } catch let error as SunsetHueError {
            return error.userMessage
        } catch {
            return "Unable to test connection."
        }
    }

    func refreshSelected(force: Bool) async {
        guard let location = selectedLocation else { return }
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            guard let apiKey = try credentialStore.loadAPIKey(), !apiKey.isEmpty else {
                bannerMessage = SunsetHueError.missingCredentials.userMessage
                state.lastErrorMessage = bannerMessage
                state.lastErrorIsAuthentication = true
                persistState()
                return
            }

            let previous = try forecastCache.loadBundle(for: location.id)
            if !force, let previous, Date().timeIntervalSince(previous.fetchedAt) < 60 {
                bundle = previous
                return
            }

            let outcome = await forecastService.refreshPreservingCache(
                location: location,
                apiKey: apiKey,
                previous: previous
            )

            if let refreshed = outcome.bundle, !outcome.usedCache {
                try forecastCache.saveBundle(refreshed)
                bundle = refreshed
                state.lastSuccessfulUpdate = refreshed.fetchedAt
                state.lastErrorMessage = nil
                state.lastErrorIsAuthentication = false
                bannerMessage = nil
                persistState()
                reloadWidgets()
            } else if let cached = outcome.bundle, outcome.usedCache {
                bundle = cached
                if let error = outcome.error {
                    bannerMessage = error.userMessage
                    state.lastErrorMessage = error.userMessage
                    state.lastErrorIsAuthentication = error.isAuthenticationFailure
                    persistState()
                    if error.isAuthenticationFailure {
                        reloadWidgets()
                    }
                }
            } else if let error = outcome.error {
                bannerMessage = error.userMessage
                state.lastErrorMessage = error.userMessage
                state.lastErrorIsAuthentication = error.isAuthenticationFailure
                persistState()
                reloadWidgets()
            }
        } catch {
            logger.error("Refresh failed unexpectedly")
            bannerMessage = SunsetHueError.networkUnavailable.userMessage
        }
    }

    private func persistState() {
        do {
            try settingsStore.save(state)
        } catch {
            logger.error("Failed to persist shared settings")
        }
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct LocationEditorDraft: Equatable {
    var id: UUID
    var name: String
    var apiKey: String
    var latitude: String
    var longitude: String
    var timeZoneIdentifier: String
    var forecastDays: Int
    var includeSunrise: Bool
    var includeSunset: Bool
    var refreshIntervalHours: Int

    static var empty: LocationEditorDraft {
        empty(apiKey: "")
    }

    static func empty(apiKey: String) -> LocationEditorDraft {
        LocationEditorDraft(
            id: UUID(),
            name: "",
            apiKey: apiKey,
            latitude: "",
            longitude: "",
            timeZoneIdentifier: TimeZone.current.identifier,
            forecastDays: 3,
            includeSunrise: true,
            includeSunset: true,
            refreshIntervalHours: 6
        )
    }

    init(location: SavedLocation, apiKey: String) {
        self.id = location.id
        self.name = location.name
        self.apiKey = apiKey
        self.latitude = String(location.latitude)
        self.longitude = String(location.longitude)
        self.timeZoneIdentifier = location.timeZoneIdentifier
        self.forecastDays = location.forecastDays
        self.includeSunrise = location.includeSunrise
        self.includeSunset = location.includeSunset
        self.refreshIntervalHours = location.refreshIntervalHours
    }

    init(
        id: UUID,
        name: String,
        apiKey: String,
        latitude: String,
        longitude: String,
        timeZoneIdentifier: String,
        forecastDays: Int,
        includeSunrise: Bool,
        includeSunset: Bool,
        refreshIntervalHours: Int
    ) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.forecastDays = forecastDays
        self.includeSunrise = includeSunrise
        self.includeSunset = includeSunset
        self.refreshIntervalHours = refreshIntervalHours
    }

    func makeLocation() throws -> SavedLocation {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SunsetHueError.invalidCoordinates
        }
        return SavedLocation(
            id: id,
            name: name,
            latitude: lat,
            longitude: lon,
            timeZoneIdentifier: timeZoneIdentifier,
            forecastDays: forecastDays,
            includeSunrise: includeSunrise,
            includeSunset: includeSunset,
            refreshIntervalHours: refreshIntervalHours
        )
    }
}
