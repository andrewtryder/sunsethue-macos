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
    @Published var snapshot: CachedLocationSnapshot?
    @Published var isRefreshing = false
    @Published var bannerMessage: String?
    @Published var isPresentingEditor = false
    @Published var editorDraft: LocationEditorDraft = .empty
    @Published var isEditingExisting = false
    @Published var lastErrorMessage: String?
    @Published var lastErrorIsAuthentication = false
    @Published var apiKeyDraft = ""
    @Published var accountStatusMessage: String?

    let settingsStore: any SharedSettingsStore
    let forecastCache: any ForecastCache
    let credentialStore: CredentialStore
    let refreshCoordinator: ForecastRefreshCoordinator
    private let logger = Logger(subsystem: "com.andrewtryder.SunsetHue", category: "App")
    private var wakeObserver: NSObjectProtocol?

    init(
        settingsStore: any SharedSettingsStore = SharedStorageFactory.makeSettingsStore(),
        forecastCache: any ForecastCache = SharedStorageFactory.makeForecastCache(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        forecastService: ForecastService = ForecastService()
    ) {
        self.settingsStore = settingsStore
        self.forecastCache = forecastCache
        self.credentialStore = credentialStore
        self.refreshCoordinator = ForecastRefreshCoordinator(
            settingsStore: settingsStore,
            forecastCache: forecastCache,
            credentialStore: credentialStore,
            forecastService: forecastService
        )
        self.state = SharedAppState()
        Task { await bootstrap() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshCoordinator.applicationDidWake()
                await self?.reloadSelectedSnapshot()
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func bootstrap() async {
        do {
            let loaded = try await settingsStore.load()
            state = loaded
            selectedLocationID = loaded.selectedLocationID ?? loaded.locations.first?.id
            await reloadSelectedSnapshot()
            await persistState()
            await refreshCoordinator.refreshAllStaleLocations()
            await reloadSelectedSnapshot()
            await refreshCoordinator.scheduleNextRefresh()
        } catch {
            logger.error("Failed to bootstrap shared storage")
            bannerMessage = SunsetHueError.storageCorrupt.userMessage
        }
    }

    var selectedLocation: SavedLocation? {
        guard let selectedLocationID else { return state.locations.first }
        return state.locations.first(where: { $0.id == selectedLocationID })
    }

    var hasAPIKey: Bool {
        do {
            return try credentialStore.loadAPIKey()?.isEmpty == false
        } catch {
            return false
        }
    }

    func applicationDidBecomeActive() {
        Task {
            await refreshCoordinator.refreshAllStaleLocations()
            await reloadSelectedSnapshot()
        }
    }

    func selectLocation(id: UUID) {
        selectedLocationID = id
        state.selectedLocationID = id
        Task {
            await persistState()
            await reloadSelectedSnapshot()
            await refreshCoordinator.refreshLocation(id: id, force: false)
            await reloadSelectedSnapshot()
        }
    }

    func selectNextLocation() {
        guard !state.locations.isEmpty else { return }
        let current = selectedLocationID.flatMap { id in state.locations.firstIndex(where: { $0.id == id }) } ?? 0
        let next = (current + 1) % state.locations.count
        selectLocation(id: state.locations[next].id)
    }

    func selectPreviousLocation() {
        guard !state.locations.isEmpty else { return }
        let current = selectedLocationID.flatMap { id in state.locations.firstIndex(where: { $0.id == id }) } ?? 0
        let previous = (current - 1 + state.locations.count) % state.locations.count
        selectLocation(id: state.locations[previous].id)
    }

    func selectLocation(at index: Int) {
        guard state.locations.indices.contains(index) else { return }
        selectLocation(id: state.locations[index].id)
    }

    func editSelectedLocation() {
        guard let location = selectedLocation else { return }
        beginEditLocation(location)
    }

    func refreshSelectedFromCommand() {
        Task { await refreshSelected(force: true) }
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
        let defaults = AppPreferenceDefaults.shared
        editorDraft = .empty(using: defaults)
        isEditingExisting = false
        isPresentingEditor = true
    }

    func beginEditLocation(_ location: SavedLocation) {
        editorDraft = LocationEditorDraft(location: location)
        isEditingExisting = true
        isPresentingEditor = true
    }

    func deleteLocation(_ location: SavedLocation) {
        state.locations.removeAll { $0.id == location.id }
        if selectedLocationID == location.id {
            selectedLocationID = state.locations.first?.id
            state.selectedLocationID = selectedLocationID
        }
        Task {
            try? await forecastCache.deleteLocation(location.id)
            await reloadSelectedSnapshot()
            await persistState()
            WidgetCenter.shared.reloadTimelines(ofKind: SunsetHueConstants.widgetKind)
            await refreshCoordinator.scheduleNextRefresh()
        }
    }

    func saveEditor() async {
        do {
            let location = try editorDraft.makeLocation().validated(againstExisting: state.locations)
            if let index = state.locations.firstIndex(where: { $0.id == location.id }) {
                state.locations[index] = location
            } else {
                state.locations.append(location)
            }
            selectedLocationID = location.id
            state.selectedLocationID = location.id
            await persistState()
            isPresentingEditor = false
            await refreshCoordinator.refreshLocation(id: location.id, force: true)
            await reloadSelectedSnapshot()
            await refreshCoordinator.scheduleNextRefresh()
        } catch let error as SunsetHueError {
            bannerMessage = error.userMessage
        } catch {
            bannerMessage = "Unable to save location."
        }
    }

    func saveAPIKey(_ key: String) async {
        do {
            try credentialStore.saveAPIKey(key)
            accountStatusMessage = "API key saved."
            apiKeyDraft = ""
            await refreshCoordinator.refreshAllStaleLocations()
            await reloadSelectedSnapshot()
            WidgetCenter.shared.reloadTimelines(ofKind: SunsetHueConstants.widgetKind)
        } catch let error as SunsetHueError {
            accountStatusMessage = error.userMessage
        } catch {
            accountStatusMessage = "Unable to save API key."
        }
    }

    func removeAPIKey() async {
        do {
            try credentialStore.deleteAPIKey()
            accountStatusMessage = "API key removed."
            lastErrorIsAuthentication = true
            lastErrorMessage = SunsetHueError.missingCredentials.userMessage
            WidgetCenter.shared.reloadTimelines(ofKind: SunsetHueConstants.widgetKind)
        } catch {
            accountStatusMessage = "Unable to remove API key."
        }
    }

    func testConnectionWithStoredOrDraftKey(_ draftKey: String?) async -> String {
        do {
            let key: String
            if let draftKey, !draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let stored = try credentialStore.loadAPIKey(), !stored.isEmpty {
                key = stored
            } else {
                return SunsetHueError.missingCredentials.userMessage
            }
            guard let location = selectedLocation ?? state.locations.first else {
                return "Add a location before testing the connection."
            }
            guard let timeZone = location.timeZone else {
                return SunsetHueError.invalidLocation("Time zone identifier is invalid.").userMessage
            }
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
        _ = await refreshCoordinator.refreshLocation(id: location.id, force: force)
        await reloadSelectedSnapshot()
        await refreshCoordinator.scheduleNextRefresh()
    }

    private func reloadSelectedSnapshot() async {
        guard let id = selectedLocationID ?? state.locations.first?.id else {
            bundle = nil
            snapshot = nil
            lastErrorMessage = nil
            lastErrorIsAuthentication = false
            return
        }
        let loaded = try? await forecastCache.loadSnapshot(for: id)
        snapshot = loaded
        bundle = loaded?.bundle
        switch loaded?.status {
        case .authenticationRequired:
            lastErrorIsAuthentication = true
            lastErrorMessage = SunsetHueError.missingCredentials.userMessage
        case .temporarilyUnavailable, .rateLimited, .stale:
            lastErrorIsAuthentication = false
            lastErrorMessage = loaded?.status == .stale ? nil : SunsetHueError.networkUnavailable.userMessage
        case .current, .none:
            lastErrorMessage = nil
            lastErrorIsAuthentication = false
        }
    }

    private func persistState() async {
        do {
            try await settingsStore.save(state)
        } catch {
            logger.error("Failed to persist shared settings")
        }
    }
}

struct AppPreferenceDefaults {
    static let shared = AppPreferenceDefaults()

    private let defaults = UserDefaults.standard

    var defaultForecastDays: Int {
        get {
            let value = defaults.object(forKey: "defaultForecastDays") as? Int
            return value ?? SunsetHueConstants.defaultForecastDays
        }
        nonmutating set { defaults.set(newValue, forKey: "defaultForecastDays") }
    }

    var defaultRefreshIntervalHours: Int {
        get {
            let value = defaults.object(forKey: "defaultRefreshIntervalHours") as? Int
            return value ?? SunsetHueConstants.defaultRefreshIntervalHours
        }
        nonmutating set { defaults.set(newValue, forKey: "defaultRefreshIntervalHours") }
    }

    var defaultIncludeSunrise: Bool {
        get {
            if defaults.object(forKey: "defaultIncludeSunrise") == nil { return true }
            return defaults.bool(forKey: "defaultIncludeSunrise")
        }
        nonmutating set { defaults.set(newValue, forKey: "defaultIncludeSunrise") }
    }

    var defaultIncludeSunset: Bool {
        get {
            if defaults.object(forKey: "defaultIncludeSunset") == nil { return true }
            return defaults.bool(forKey: "defaultIncludeSunset")
        }
        nonmutating set { defaults.set(newValue, forKey: "defaultIncludeSunset") }
    }

    var openMainWindowOnLaunch: Bool {
        get {
            if defaults.object(forKey: "openMainWindowOnLaunch") == nil { return true }
            return defaults.bool(forKey: "openMainWindowOnLaunch")
        }
        nonmutating set { defaults.set(newValue, forKey: "openMainWindowOnLaunch") }
    }
}

struct LocationEditorDraft: Equatable {
    var id: UUID
    var name: String
    var latitude: String
    var longitude: String
    var timeZoneIdentifier: String
    var forecastDays: Int
    var includeSunrise: Bool
    var includeSunset: Bool
    var refreshIntervalHours: Int

    static var empty: LocationEditorDraft {
        empty(using: .shared)
    }

    static func empty(using defaults: AppPreferenceDefaults) -> LocationEditorDraft {
        LocationEditorDraft(
            id: UUID(),
            name: "",
            latitude: "",
            longitude: "",
            timeZoneIdentifier: TimeZone.current.identifier,
            forecastDays: defaults.defaultForecastDays,
            includeSunrise: defaults.defaultIncludeSunrise,
            includeSunset: defaults.defaultIncludeSunset,
            refreshIntervalHours: defaults.defaultRefreshIntervalHours
        )
    }

    init(location: SavedLocation) {
        self.id = location.id
        self.name = location.name
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
