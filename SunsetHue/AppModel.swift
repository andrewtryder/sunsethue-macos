import AppKit
import Foundation
import SwiftUI
import SunsetHueCore
import os

@MainActor
final class AppModel: ObservableObject {
    @Published var state: SharedAppState
    @Published var selectedLocationID: UUID?
    @Published var bundle: LocationForecastBundle?
    @Published var snapshot: CachedLocationSnapshot?
    @Published var snapshotsByLocationID: [UUID: CachedLocationSnapshot] = [:]
    @Published var isRefreshing = false
    @Published var bannerMessage: String?
    @Published var isPresentingEditor = false
    @Published var editorDraft: LocationEditorDraft = .empty
    @Published var isEditingExisting = false
    @Published var lastErrorMessage: String?
    @Published var lastErrorIsAuthentication = false
    @Published var apiKeyDraft = ""
    @Published var accountStatusMessage: String?
    @Published var credentialState: CredentialState = .unknown
    @Published var diagnosticsExportMessage: String?
    @Published var notificationPreferences = NotificationPreferences()
    @Published var notificationAuthorization: ForecastNotificationCoordinator.AuthorizationState = .notDetermined
    @Published var notificationStatusMessage: String?
    @Published var notificationTestResult: NotificationTestResult?
    @Published var isNotificationTestRunning = false
    @Published private(set) var refreshingLocationIDs: Set<UUID> = []
    @Published var lastNotificationDiagnostics: NotificationDiagnosticsSnapshot?

    let settingsStore: any SharedSettingsStore
    let forecastCache: any ForecastCache
    let credentialStore: CredentialStore
    let refreshCoordinator: ForecastRefreshCoordinator
    let notificationCoordinator: ForecastNotificationCoordinator
    private let backgroundRefreshController: BackgroundRefreshController
    private let sideEffectBox = ForecastRefreshSideEffectBox()
    private let logger = Logger(subsystem: "com.andrewtryder.SunsetHue", category: "App")
    private var wakeObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?

    init(
        settingsStore: any SharedSettingsStore = SharedStorageFactory.makeSettingsStore(),
        forecastCache: any ForecastCache = SharedStorageFactory.makeForecastCache(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        forecastService: ForecastService = ForecastService()
    ) {
        self.settingsStore = settingsStore
        self.forecastCache = forecastCache
        self.credentialStore = credentialStore
        self.notificationCoordinator = ForecastNotificationCoordinator()
        let coordinator = ForecastRefreshCoordinator(
            settingsStore: settingsStore,
            forecastCache: forecastCache,
            credentialStore: credentialStore,
            forecastService: forecastService,
            sideEffectSink: sideEffectBox
        )
        self.refreshCoordinator = coordinator
        self.backgroundRefreshController = BackgroundRefreshController(refreshCoordinator: coordinator)
        self.state = SharedAppState()
        sideEffectBox.impl = AppForecastRefreshSideEffects(
            notificationCoordinator: notificationCoordinator,
            settingsStore: settingsStore,
            forecastCache: forecastCache
        ) { [weak self] in
            await self?.reloadSelectedSnapshot()
        }
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
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCredentialState()
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
        }
    }

    private func bootstrap() async {
        AppSupportPaths.migrateUnsignedStorageToTeamGroupIfNeeded()
        do {
            let loaded = try await settingsStore.load()
            state = loaded.value
            if let recovery = loaded.recovery {
                bannerMessage = recovery.userMessage
            }
            selectedLocationID = loaded.value.selectedLocationID ?? loaded.value.locations.first?.id
            refreshCredentialState()
            await reloadNotificationState()
            await reloadSelectedSnapshot()
            await persistState()
            await refreshCoordinator.refreshAllStaleLocations(trigger: .bootstrap)
            await reloadSelectedSnapshot()
            await refreshCoordinator.scheduleNextRefresh()
            await rescheduleNotifications()
            backgroundRefreshController.start()
        } catch {
            logger.error("Failed to bootstrap shared storage")
            bannerMessage = SunsetHueError.storageCorrupt.userMessage
            refreshCredentialState()
        }
    }

    var selectedLocation: SavedLocation? {
        guard let selectedLocationID else { return state.locations.first }
        return state.locations.first(where: { $0.id == selectedLocationID })
    }

    public typealias MenuBarPopoverRow = SunsetHueCore.MenuBarPopoverRow

    /// Compact rows per configured location for the menu-bar window popup.
    func menuBarPopoverRows(
        preferences: MenuBarPreferences,
        now: Date = Date()
    ) -> [MenuBarPopoverRow] {
        MenuBarPopoverPresenter.buildRows(
            locations: state.locations,
            snapshots: snapshotsByLocationID,
            preferences: preferences,
            selectedLocationID: selectedLocationID,
            refreshingLocationIDs: refreshingLocationIDs,
            now: now
        )
    }

    func refreshLocationFromMenuBar(id: UUID) {
        Task {
            refreshingLocationIDs.insert(id)
            defer { refreshingLocationIDs.remove(id) }
            _ = await refreshCoordinator.refreshLocation(id: id, force: true, trigger: .manual)
            await reloadSelectedSnapshot()
        }
    }

    var hasAPIKey: Bool {
        credentialState == .configured
    }

    func refreshCredentialState() {
        do {
            let key = try credentialStore.loadAPIKey()
            credentialState = (key?.isEmpty == false) ? .configured : .missing
        } catch let error as SunsetHueError where error == .keychainUnavailable {
            credentialState = .unavailable
        } catch {
            credentialState = .unavailable
        }
    }

    func applicationDidBecomeActive() {
        refreshCredentialState()
        Task {
            await refreshCoordinator.refreshAllStaleLocations(trigger: .didBecomeActive)
            await reloadSelectedSnapshot()
        }
    }

    func refreshAllFromCommand() {
        Task {
            await refreshCoordinator.refreshAllStaleLocations(trigger: .manual)
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
            await notificationCoordinator.removeNotifications(for: location.id)
            await reloadSelectedSnapshot()
            await persistState()
            WidgetReload.timelines()
            await refreshCoordinator.scheduleNextRefresh()
            await rescheduleNotifications()
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
            refreshCredentialState()
            await refreshCoordinator.refreshAuthenticationRequiredLocations()
            await refreshCoordinator.refreshAllStaleLocations()
            await reloadSelectedSnapshot()
            WidgetReload.timelines()
            await rescheduleNotifications()
        } catch let error as SunsetHueError {
            refreshCredentialState()
            accountStatusMessage = error.userMessage
        } catch {
            refreshCredentialState()
            accountStatusMessage = "Unable to save API key."
        }
    }

    func removeAPIKey() async {
        do {
            try credentialStore.deleteAPIKey()
            accountStatusMessage = "API key removed."
            refreshCredentialState()
            lastErrorIsAuthentication = true
            lastErrorMessage = SunsetHueError.missingCredentials.userMessage
            await refreshCoordinator.markAllSnapshotsAuthenticationRequired()
            await reloadSelectedSnapshot()
            WidgetReload.timelines()
        } catch {
            refreshCredentialState()
            accountStatusMessage = "Unable to remove API key."
        }
    }

    func reloadNotificationState() async {
        notificationPreferences = await notificationCoordinator.loadPreferences()
        await notificationCoordinator.refreshAuthorizationStatus()
        notificationAuthorization = await notificationCoordinator.authorizationState
    }

    func moveLocations(from indices: IndexSet, to newOffset: Int) {
        state.moveLocations(fromOffsets: indices, toOffset: newOffset)
        Task {
            await persistState()
            WidgetReload.timelines()
        }
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) async {
        var next = preferences
        let previous = notificationPreferences
        let enablingNotifications =
            (next.notificationsEnabled && !previous.notificationsEnabled)
            || (next.dailySummary.enabled && !previous.dailySummary.enabled)
            || (next.dailySummary.secondTimeEnabled && !previous.dailySummary.secondTimeEnabled)
            || (next.qualityAlert.enabled && !previous.qualityAlert.enabled)

        let wantsNotifications =
            next.notificationsEnabled
            || next.dailySummary.enabled
            || next.qualityAlert.enabled
            || next.dailySummary.secondTimeEnabled

        if wantsNotifications {
            let result = (try? await notificationCoordinator.ensureAuthorization()) ?? .unavailable
            await notificationCoordinator.refreshAuthorizationStatus()
            notificationAuthorization = await notificationCoordinator.authorizationState
            if enablingNotifications, result == .denied {
                notificationStatusMessage =
                    "Notifications are disabled in System Settings. Use “Open System Notification Settings…” to enable them."
            }
        }

        // Bump quality revision when threshold or event mode changes.
        if next.qualityAlert.threshold != previous.qualityAlert.threshold
            || next.qualityAlert.eventMode != previous.qualityAlert.eventMode {
            next.qualityAlert.revision += 1
        }

        if next.locationID == nil {
            next.locationID = selectedLocationID ?? state.locations.first?.id
        }

        if let locID = next.locationID {
            var currentRule = next.rule(for: locID)
            currentRule.dailySummary = next.dailySummary
            currentRule.qualityAlert = next.qualityAlert
            next.setRule(currentRule, for: locID)
        }

        await notificationCoordinator.savePreferences(next)
        notificationPreferences = next
        await notificationCoordinator.refreshAuthorizationStatus()
        notificationAuthorization = await notificationCoordinator.authorizationState
        await rescheduleNotifications()
    }

    func sendTestNotification() async {
        guard !isNotificationTestRunning else { return }
        isNotificationTestRunning = true
        notificationStatusMessage = nil
        notificationTestResult = NotificationTestResult(
            stage: .checkingSettings,
            message: "Checking notification settings…"
        )
        defer { isNotificationTestRunning = false }

        let locationName = notificationLocation?.name ?? "SunsetHue"
        let playSound = notificationPreferences.playSound

        let result = await notificationCoordinator.runTestNotification(
            locationName: locationName,
            playSound: playSound
        ) { [weak self] progress in
            Task { @MainActor in
                self?.notificationTestResult = progress
                self?.notificationStatusMessage = progress.message
            }
        }

        notificationTestResult = result
        notificationStatusMessage = result.message
        lastNotificationDiagnostics = await buildNotificationDiagnostics(for: result)
        await reloadNotificationState()
    }

    func copyNotificationDiagnosticsToPasteboard() async {
        let snapshot: NotificationDiagnosticsSnapshot
        if let existing = lastNotificationDiagnostics {
            snapshot = existing
        } else {
            snapshot = await buildNotificationDiagnostics(for: notificationTestResult)
        }
        lastNotificationDiagnostics = snapshot
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.copyText(), forType: .string)
        notificationStatusMessage = "Notification diagnostics copied."
    }

    private func buildNotificationDiagnostics(
        for result: NotificationTestResult?
    ) async -> NotificationDiagnosticsSnapshot {
        let settings = await SystemNotificationCenterClient().notificationSettings()
        let executable = Bundle.main.executableURL?.path
        let runningFromApps = (executable?.hasPrefix("/Applications/") == true)
            || (Bundle.main.bundlePath.hasPrefix("/Applications/"))
        let team = SunsetHueConstants.teamIdentifier
        let pending: Bool?
        let delivered: Bool?
        if let id = result?.requestIdentifier {
            let client = SystemNotificationCenterClient()
            let pendingIDs = await client.pendingIdentifiers()
            let deliveredIDs = await client.deliveredIdentifiers()
            pending = pendingIDs.contains(id)
            delivered = deliveredIDs.contains(id)
        } else {
            pending = nil
            delivered = nil
        }

        return NotificationDiagnosticsSnapshot(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            executablePath: executable,
            runningFromApplications: runningFromApps,
            teamIdentifierPresent: !(team?.isEmpty ?? true),
            teamIdentifier: team?.isEmpty == false ? team : nil,
            authorizationStatus: settings.authorizationStatus.rawValue,
            alertSetting: settings.alertSetting.rawValue,
            notificationCenterSetting: settings.notificationCenterSetting.rawValue,
            soundSetting: settings.soundSetting.rawValue,
            lockScreenSetting: settings.lockScreenSetting.rawValue,
            testRequestPending: pending,
            foregroundDelegateReceived: result?.stage == .foregroundDelegateReceived
                || result?.stage == .confirmedDelivered,
            testRequestDelivered: delivered,
            lastTestStage: result.map { String(describing: $0.stage) },
            lastTestMessage: result?.message
        )
    }

    func openSystemNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.andrewtryder.SunsetHue"
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.Notifications-Settings?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.Notifications-Settings",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    var notificationLocation: SavedLocation? {
        if let id = notificationPreferences.locationID {
            return state.locations.first(where: { $0.id == id })
        }
        return selectedLocation ?? state.locations.first
    }

    func rescheduleNotifications() async {
        await notificationCoordinator.rescheduleDailyNotifications(
            state: state,
            snapshots: snapshotsByLocationID
        )
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
        var all: [UUID: CachedLocationSnapshot] = [:]
        for location in state.locations {
            if let snap = try? await forecastCache.loadSnapshot(for: location.id) {
                all[location.id] = snap
            }
        }
        snapshotsByLocationID = all

        guard let id = selectedLocationID ?? state.locations.first?.id else {
            bundle = nil
            snapshot = nil
            lastErrorMessage = nil
            lastErrorIsAuthentication = false
            return
        }
        let loaded = all[id]
        snapshot = loaded
        bundle = loaded?.bundle
        switch loaded?.status {
        case .authenticationRequired:
            lastErrorIsAuthentication = true
            if credentialState == .unavailable {
                lastErrorMessage = SunsetHueError.keychainUnavailable.userMessage
            } else {
                lastErrorMessage = SunsetHueError.missingCredentials.userMessage
            }
        case .rateLimited(let retryAfter):
            lastErrorIsAuthentication = false
            if let retryAfter {
                lastErrorMessage = "Rate limited until \(retryAfter.formatted(date: .omitted, time: .shortened))."
            } else {
                lastErrorMessage = SunsetHueError.rateLimited(retryAfter: nil).userMessage
            }
        case .temporarilyUnavailable:
            lastErrorIsAuthentication = false
            lastErrorMessage = SunsetHueError.networkUnavailable.userMessage
        case .invalidRequest:
            lastErrorIsAuthentication = false
            lastErrorMessage = SunsetHueError.invalidCoordinates.userMessage
        case .invalidResponse:
            lastErrorIsAuthentication = false
            lastErrorMessage = "SunsetHue returned an incompatible response."
        case .stale:
            lastErrorIsAuthentication = false
            lastErrorMessage = nil
        case .current, .none:
            lastErrorMessage = nil
            lastErrorIsAuthentication = false
        }
    }

    func storageDiagnostics() -> StorageDiagnostics {
        let (mode, _) = StoragePathResolver().resolveContainerURL()
        let modeName: String
        let appGroupID: String?
        let isAppGroupAvailable: Bool
        switch mode {
        case .teamAppGroup(let id):
            modeName = "Personal Team App Group"
            appGroupID = id
            isAppGroupAvailable = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil
        case .localApplicationSupport:
            modeName = "Local Application Support"
            appGroupID = nil
            isAppGroupAvailable = false
        }
        let isSettingsReadable = (try? Data(contentsOf: StoragePathResolver().settingsURL())) != nil
        let isCacheReadable = FileManager.default.fileExists(atPath: StoragePathResolver().cacheDirectoryURL().path)
        return StorageDiagnostics(
            storageMode: mode,
            storageModeDisplayName: modeName,
            appGroupIdentifier: appGroupID,
            isAppGroupAvailable: isAppGroupAvailable,
            isSettingsReadable: isSettingsReadable,
            isForecastCacheReadable: isCacheReadable,
            lastCacheCommit: WidgetReloadStateTracker.shared.lastCacheCommit,
            lastWidgetReloadRequested: WidgetReloadStateTracker.shared.lastReloadRequested
        )
    }

    func backgroundRefreshDiagnostics() -> BackgroundRefreshDiagnostics {
        BackgroundRefreshDiagnostics(
            isActive: backgroundRefreshController.isActive,
            schedulerName: "NSBackgroundActivityScheduler",
            intervalDescription: "~30 min",
            lastActivityAt: backgroundRefreshController.lastActivityAt,
            lastDisposition: backgroundRefreshController.lastDisposition,
            isLaunchAtLoginEnabled: LaunchAtLoginController().isEnabled
        )
    }

    func locationDiagnostics() -> [LocationRefreshDiagnostics] {
        state.locations.map { loc in
            LocationRefreshDiagnostics.make(
                location: loc,
                snapshot: snapshotsByLocationID[loc.id] ?? (loc.id == selectedLocationID ? snapshot : nil),
                isRefreshing: refreshingLocationIDs.contains(loc.id) || isRefreshing
            )
        }
    }

    func recentActivities() async -> [RefreshActivityRecord] {
        await refreshCoordinator.activityRecorder.recentEntries()
    }

    func copyDiagnosticsToPasteboard(includeApproximateCoordinates: Bool = false) async -> String {
        let exporter = DiagnosticsExporter()
        let storageDiag = storageDiagnostics()
        let bgDiag = backgroundRefreshDiagnostics()
        let recent = await recentActivities()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SunsetHueConstants.marketingVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let authDesc: String = {
            switch notificationAuthorization {
            case .authorized: return "Authorized"
            case .denied: return "Denied"
            case .notDetermined: return "Not Determined"
            case .provisional: return "Provisional"
            case .ephemeral: return "Ephemeral"
            }
        }()

        do {
            let text = try exporter.makePlainTextDiagnostics(
                state: state,
                snapshots: snapshotsByLocationID,
                storageDiagnostics: storageDiag,
                backgroundDiagnostics: bgDiag,
                recentActivity: recent,
                notificationPreferences: notificationPreferences,
                notificationAuthorization: authDesc,
                apiKeyConfigured: hasAPIKey,
                appVersion: version,
                build: build,
                options: DiagnosticsExportOptions(includeApproximateCoordinates: includeApproximateCoordinates)
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return "Diagnostics copied to clipboard."
        } catch {
            return "Unable to copy diagnostics."
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

@MainActor
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

    @MainActor
    static var empty: LocationEditorDraft {
        empty(using: .shared)
    }

    @MainActor
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
