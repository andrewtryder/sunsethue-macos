import SwiftUI
import AppKit
import SunsetHueCore

struct SunsetHueSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var menuBarPreferencesStore: MenuBarPreferencesStore
    @ObservedObject var menuBarLabelController: MenuBarLabelController
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("menuBarOnlyMode") private var menuBarOnlyMode = false
    @AppStorage("diagnosticsIncludeApproximateCoordinates") private var includeApproximateCoordinates = false
    @AppStorage("autoCheckUpdatesDaily") private var autoCheckUpdatesDaily = true
    @AppStorage("lastUpdateCheckDay") private var lastUpdateCheckDay = ""
    @AppStorage("selectedSettingsTab") private var selectedSettingsTab = SettingsTab.general.rawValue
    @State private var updateMessage: String?
    @State private var latestVersion: String?
    @State private var isCheckingUpdates = false
    @State private var accountTestMessage: String?
    @State private var isTestingAccount = false
    @State private var diagnosticsMessage: String?
    @State private var recentActivities: [RefreshActivityRecord] = []
    @FocusState private var isAPIKeyFieldFocused: Bool
    @State private var isReplacingAPIKey = false
    @State private var confirmRemoveAPIKey = false

    private enum SettingsTab: String {
        case general
        case account
        case notifications
        case updates
        case diagnostics
    }

    var body: some View {
        TabView(selection: Binding(
            get: { SettingsTab(rawValue: selectedSettingsTab) ?? .general },
            set: { selectedSettingsTab = $0.rawValue }
        )) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            accountTab
                .tabItem { Label("Account", systemImage: "key") }
                .tag(SettingsTab.account)
            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
                .tag(SettingsTab.updates)
            diagnosticsTab
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(SettingsTab.diagnostics)
        }
        .frame(width: 520, height: 580)
        .onAppear {
            launchAtLogin.refresh()
            Task {
                await appModel.reloadNotificationState()
                await maybeAutoCheckUpdates()
            }
        }
    }

    private var notificationsTab: some View {
        Form {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    StatusBadge(
                        title: notificationStatusLabel,
                        tone: notificationStatusTone,
                        accessibilityLabelText: "Notification authorization",
                        accessibilityValueText: notificationStatusLabel
                    )
                }
                Button("Open System Notification Settings…") {
                    appModel.openSystemNotificationSettings()
                }
                if appModel.notificationAuthorization == .denied {
                    Text("Notifications are disabled in System Settings. Enable SunsetHue there to deliver alerts.")
                        .sunsetHueMuted()
                } else if appModel.notificationAuthorization == .notDetermined {
                    Text("Turning on notifications will ask for permission.")
                        .sunsetHueMuted()
                }
                Toggle("Enable notifications", isOn: notificationMasterBinding)
                if appModel.state.locations.isEmpty {
                    Text("Add a location before configuring notification delivery.")
                        .sunsetHueMuted()
                } else {
                    Picker("Location", selection: notificationLocationBinding) {
                        ForEach(appModel.state.locations) { location in
                            Text(location.name).tag(Optional(location.id))
                        }
                    }
                }
            }

            Section("Daily summaries") {
                Toggle("Send first summary at", isOn: dailyFirstEnabledBinding)
                DatePicker(
                    "First time",
                    selection: minutesBinding(\.dailySummary.firstTimeMinutes),
                    displayedComponents: .hourAndMinute
                )
                .sunsetHueDisabledDim(!appModel.notificationPreferences.dailySummary.enabled)
                Toggle("Send second summary at", isOn: dailySecondEnabledBinding)
                DatePicker(
                    "Second time",
                    selection: minutesBinding(\.dailySummary.secondTimeMinutes),
                    displayedComponents: .hourAndMinute
                )
                .sunsetHueDisabledDim(!appModel.notificationPreferences.dailySummary.secondTimeEnabled)
                if let tz = appModel.notificationLocation?.timeZoneIdentifier {
                    Text("Times use \(tz)")
                        .sunsetHueMuted()
                }
            }

            Section("Quality alerts") {
                Toggle("Notify when quality reaches threshold", isOn: qualityEnabledBinding)
                Picker("Event", selection: qualityEventBinding) {
                    ForEach(NotificationEventMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .sunsetHueDisabledDim(!appModel.notificationPreferences.qualityAlert.enabled)
                Picker("Threshold", selection: qualityThresholdBinding) {
                    ForEach(Array(stride(from: 50, through: 100, by: 5)), id: \.self) { percent in
                        Text("\(percent)%").tag(Double(percent) / 100.0)
                    }
                }
                .sunsetHueDisabledDim(!appModel.notificationPreferences.qualityAlert.enabled)
                Text("Only once per sunrise or sunset forecast occurrence.")
                    .sunsetHueMuted()
                Text("Quality alerts are evaluated while SunsetHue is running (Launch at Login makes this more reliable). Daily summaries can still deliver after you quit.")
                    .sunsetHueMuted()
            }

            Section {
                Toggle("Play sound", isOn: playSoundBinding)
                Button(appModel.isNotificationTestRunning ? "Testing…" : "Send Test Notification") {
                    Task { await appModel.sendTestNotification() }
                }
                .disabled(appModel.isNotificationTestRunning)
                if let result = appModel.notificationTestResult {
                    Text("Stage: \(notificationTestStageLabel(result.stage))")
                        .font(.caption.weight(.semibold))
                    Text(result.message)
                        .sunsetHueMuted()
                        .accessibilityLabel(result.message)
                } else if let notificationStatusMessage = appModel.notificationStatusMessage {
                    Text(notificationStatusMessage)
                        .sunsetHueMuted()
                        .accessibilityLabel(notificationStatusMessage)
                }
                Button("Copy Notification Diagnostics") {
                    Task { await appModel.copyNotificationDiagnosticsToPasteboard() }
                }
                Text("A test notification can be sent even when daily summaries and quality alerts are off. Delivery depends on macOS Focus and banner settings; unsigned builds may be suppressed.")
                    .sunsetHueMuted()
            }
        }
        .formStyle(.grouped)
    }

    private var notificationStatusLabel: String {
        switch appModel.notificationAuthorization {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested"
        }
    }

    private var notificationStatusTone: StatusTone {
        switch appModel.notificationAuthorization {
        case .authorized, .provisional, .ephemeral: return .positive
        case .denied: return .warning
        case .notDetermined: return .neutral
        }
    }

    private var notificationMasterBinding: Binding<Bool> {
        Binding(
            get: { appModel.notificationPreferences.notificationsEnabled },
            set: { enabled in
                var prefs = appModel.notificationPreferences
                prefs.notificationsEnabled = enabled
                if enabled, prefs.locationID == nil {
                    prefs.locationID = appModel.selectedLocationID ?? appModel.state.locations.first?.id
                }
                Task { await appModel.updateNotificationPreferences(prefs) }
            }
        )
    }

    private var notificationLocationBinding: Binding<UUID?> {
        Binding(
            get: { appModel.notificationPreferences.locationID ?? appModel.selectedLocationID },
            set: { id in
                var prefs = appModel.notificationPreferences
                prefs.locationID = id
                if let id {
                    let rule = prefs.rule(for: id)
                    prefs.dailySummary = rule.dailySummary
                    prefs.qualityAlert = rule.qualityAlert
                }
                Task { await appModel.updateNotificationPreferences(prefs) }
            }
        )
    }

    private var dailyFirstEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.notificationPreferences.dailySummary.enabled },
            set: { enabled in
                var prefs = appModel.notificationPreferences
                prefs.dailySummary.enabled = enabled
                if enabled { prefs.notificationsEnabled = true }
                Task { await appModel.updateNotificationPreferences(prefs) }
            }
        )
    }

    private var dailySecondEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.notificationPreferences.dailySummary.secondTimeEnabled },
            set: { enabled in
                var prefs = appModel.notificationPreferences
                prefs.dailySummary.secondTimeEnabled = enabled
                if enabled {
                    prefs.dailySummary.enabled = true
                    prefs.notificationsEnabled = true
                }
                Task { await appModel.updateNotificationPreferences(prefs) }
            }
        )
    }

    private var qualityEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.notificationPreferences.qualityAlert.enabled },
            set: { enabled in
                var prefs = appModel.notificationPreferences
                prefs.qualityAlert.enabled = enabled
                if enabled { prefs.notificationsEnabled = true }
                Task { await appModel.updateNotificationPreferences(prefs) }
            }
        )
    }

    private var qualityEventBinding: Binding<NotificationEventMode> {
        Binding(
            get: { appModel.notificationPreferences.qualityAlert.eventMode },
            set: { mode in
                var prefs = appModel.notificationPreferences
                prefs.qualityAlert.eventMode = mode
                Task { await appModel.updateNotificationPreferences(prefs) }
            }
        )
    }

    private var qualityThresholdBinding: Binding<Double> {
        Binding(
            get: { appModel.notificationPreferences.qualityAlert.threshold },
            set: { value in
                var prefs = appModel.notificationPreferences
                prefs.qualityAlert.threshold = value
                Task { await appModel.updateNotificationPreferences(prefs) }
            }
        )
    }

    private var playSoundBinding: Binding<Bool> {
        Binding(
            get: { appModel.notificationPreferences.playSound },
            set: { value in
                var prefs = appModel.notificationPreferences
                prefs.playSound = value
                Task { await appModel.updateNotificationPreferences(prefs) }
            }
        )
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<NotificationPreferences, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = appModel.notificationPreferences[keyPath: keyPath]
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: Date())
                return calendar.date(byAdding: .minute, value: minutes, to: start) ?? Date()
            },
            set: { date in
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: date)
                let minutes = Int(date.timeIntervalSince(start) / 60)
                var prefs = appModel.notificationPreferences
                prefs[keyPath: keyPath] = min(max(0, minutes), (23 * 60) + 59)
                Task { await appModel.updateNotificationPreferences(prefs) }
            }
        )
    }

    private func notificationTestStageLabel(_ stage: NotificationTestResult.Stage) -> String {
        switch stage {
        case .checkingSettings: return "Checking settings"
        case .requestingAuthorization: return "Requesting authorization"
        case .scheduled: return "Scheduled"
        case .confirmedPending: return "Confirmed pending"
        case .foregroundDelegateReceived: return "Foreground delegate received"
        case .confirmedDelivered: return "Delivered"
        case .suppressed: return "Suppressed"
        case .failed: return "Failed"
        }
    }

    private var menuBarPreview: some View {
        let preferences = menuBarPreferencesStore.preferences
        let status: MenuBarStatus = {
            if let location = appModel.selectedLocation ?? appModel.state.locations.first {
                let item = MenuBarForecastResolver.resolve(
                    location: location,
                    snapshot: appModel.snapshotsByLocationID[location.id] ?? appModel.snapshot,
                    selection: preferences.eventSelection,
                    now: Date()
                )
                return MenuBarStatus.from(
                    location: location,
                    item: item,
                    snapshot: appModel.snapshotsByLocationID[location.id] ?? appModel.snapshot,
                    selection: preferences.eventSelection
                )
            }
            // Fixture-style preview when no locations exist.
            return MenuBarStatus(
                locationName: "Sandown",
                eventType: .sunset,
                quality: 0.82,
                eventTime: Date(),
                timeZone: .current,
                message: nil
            )
        }()
        let title = MenuBarStatusFormatting.labelText(for: status, style: preferences.displayStyle)
        return HStack(spacing: 8) {
            Text("Preview:")
                .foregroundStyle(.secondary)
            Label(title.isEmpty ? " " : title, systemImage: status.symbolName)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Menu bar label preview")
        .accessibilityValue(MenuBarStatusFormatting.accessibilityLabel(for: status, style: preferences.displayStyle))
    }

    private var generalTab: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show SunsetHue in menu bar", isOn: Binding(
                    get: { showMenuBarExtra },
                    set: { newValue in
                        if !newValue, menuBarOnlyMode {
                            launchAtLogin.errorMessage =
                                "Turn off “Run as menu bar-only app” before hiding the menu bar icon."
                            return
                        }
                        if !newValue,
                           !AppPreferenceDefaults.shared.openMainWindowOnLaunch,
                           launchAtLogin.isEnabled {
                            launchAtLogin.errorMessage =
                                "Keep the menu bar icon, the main window on launch, or turn off Launch at Login so SunsetHue stays reachable."
                            return
                        }
                        showMenuBarExtra = newValue
                    }
                ))
                .disabled(menuBarOnlyMode)

                Picker(
                    "Menu bar label",
                    selection: Binding(
                        get: { menuBarPreferencesStore.preferences.displayStyle },
                        set: { style in
                            menuBarPreferencesStore.update { $0.displayStyle = style }
                            menuBarLabelController.refreshNow()
                        }
                    )
                ) {
                    ForEach(MenuBarDisplayStyle.allCases, id: \.self) { style in
                        Text(style.settingsLabel).tag(style)
                    }
                }

                Picker(
                    "Event shown",
                    selection: Binding(
                        get: { menuBarPreferencesStore.preferences.eventSelection },
                        set: { selection in
                            menuBarPreferencesStore.update { $0.eventSelection = selection }
                            menuBarLabelController.refreshNow()
                        }
                    )
                ) {
                    ForEach(MenuBarEventSelection.allCases, id: \.self) { selection in
                        Text(selection.settingsLabel).tag(selection)
                    }
                }

                Picker(
                    "Location behavior",
                    selection: Binding(
                        get: { menuBarPreferencesStore.preferences.locationMode },
                        set: { mode in
                            menuBarPreferencesStore.update { $0.locationMode = mode }
                            menuBarLabelController.refreshNow()
                        }
                    )
                ) {
                    ForEach(MenuBarLocationMode.allCases, id: \.self) { mode in
                        Text(mode.settingsLabel).tag(mode)
                    }
                }

                if appModel.state.locations.count > 1,
                   menuBarPreferencesStore.preferences.locationMode == .rotateLocations {
                    Picker(
                        "Rotate every",
                        selection: Binding(
                            get: { menuBarPreferencesStore.preferences.rotationIntervalSeconds },
                            set: { seconds in
                                menuBarPreferencesStore.update { $0.rotationIntervalSeconds = seconds }
                                menuBarLabelController.refreshNow()
                            }
                        )
                    ) {
                        ForEach(MenuBarPreferences.allowedRotationIntervals, id: \.self) { seconds in
                            Text("\(seconds) seconds").tag(seconds)
                        }
                    }
                }

                menuBarPreview

                Toggle("Run as menu bar-only app", isOn: Binding(
                    get: { menuBarOnlyMode },
                    set: { enabled in
                        if enabled {
                            showMenuBarExtra = true
                            AppPreferenceDefaults.shared.openMainWindowOnLaunch = false
                        }
                        menuBarOnlyMode = enabled
                        AppPresentationModeController.apply(menuBarOnly: enabled)
                    }
                ))
                Text(
                    "Hides SunsetHue from the Dock and macOS application menu. "
                        + "The main window and Settings remain available from the menu-bar icon."
                )
                .sunsetHueMuted()
            }

            Section("App Behavior") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { enabled in
                        if enabled,
                           !showMenuBarExtra,
                           !AppPreferenceDefaults.shared.openMainWindowOnLaunch {
                            launchAtLogin.errorMessage =
                                "Enable the menu bar icon or “Open main window when launched” before turning on Launch at Login."
                            return
                        }
                        launchAtLogin.setEnabled(enabled)
                    }
                ))
                if launchAtLogin.status == .requiresApproval {
                    Text("Launch at Login requires approval in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Open Login Items…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if launchAtLogin.status == .unavailable {
                    Text("Launch at Login is unavailable for this build.")
                        .sunsetHueMuted()
                } else {
                    Text("Recommended if you use widgets. Keeps forecasts updated in the background even when you haven't opened SunsetHue.")
                        .sunsetHueMuted()
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Open main window when launched", isOn: Binding(
                    get: { AppPreferenceDefaults.shared.openMainWindowOnLaunch },
                    set: { newValue in
                        if newValue, menuBarOnlyMode {
                            launchAtLogin.errorMessage =
                                "Turn off “Run as menu bar-only app” before opening the main window on launch."
                            return
                        }
                        if !newValue, !showMenuBarExtra, launchAtLogin.isEnabled {
                            launchAtLogin.errorMessage =
                                "Keep the menu bar icon or turn off Launch at Login before disabling the main window on launch."
                            return
                        }
                        AppPreferenceDefaults.shared.openMainWindowOnLaunch = newValue
                    }
                ))
                .disabled(menuBarOnlyMode)
            }
            Section("Defaults for new locations") {
                Picker(
                    "Forecast days",
                    selection: Binding(
                        get: { AppPreferenceDefaults.shared.defaultForecastDays },
                        set: { AppPreferenceDefaults.shared.defaultForecastDays = $0 }
                    )
                ) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                Picker(
                    "Refresh interval",
                    selection: Binding(
                        get: { AppPreferenceDefaults.shared.defaultRefreshIntervalHours },
                        set: { AppPreferenceDefaults.shared.defaultRefreshIntervalHours = $0 }
                    )
                ) {
                    Text("6 hours").tag(6)
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                }
                Toggle("Include sunrise", isOn: Binding(
                    get: { AppPreferenceDefaults.shared.defaultIncludeSunrise },
                    set: { AppPreferenceDefaults.shared.defaultIncludeSunrise = $0 }
                ))
                Toggle("Include sunset", isOn: Binding(
                    get: { AppPreferenceDefaults.shared.defaultIncludeSunset },
                    set: { AppPreferenceDefaults.shared.defaultIncludeSunset = $0 }
                ))
                Text("These defaults apply only to newly added locations.")
                    .sunsetHueMuted()
            }
        }
        .formStyle(.grouped)
    }

    private var accountTab: some View {
        Form {
            Section("API key") {
                HStack {
                    Text("Status")
                    Spacer()
                    StatusBadge(
                        title: credentialStatusLabel,
                        tone: credentialStatusTone,
                        accessibilityLabelText: "API key status",
                        accessibilityValueText: credentialStatusLabel
                    )
                }

                if appModel.hasAPIKey && !isReplacingAPIKey {
                    Text("••••••••••")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("API key saved")
                    Text("API key saved in the Keychain.")
                        .sunsetHueMuted()
                    HStack {
                        Button("Replace Key") {
                            isReplacingAPIKey = true
                            appModel.apiKeyDraft = ""
                            isAPIKeyFieldFocused = true
                        }
                        Button("Test Connection") {
                            Task {
                                isTestingAccount = true
                                accountTestMessage = await appModel.testConnectionWithStoredOrDraftKey(nil)
                                isTestingAccount = false
                            }
                        }
                        .disabled(isTestingAccount)
                        Button("Remove Key", role: .destructive) {
                            confirmRemoveAPIKey = true
                        }
                    }
                } else {
                    SecureField("Paste your SunsetHue API key", text: $appModel.apiKeyDraft)
                        .focused($isAPIKeyFieldFocused)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("API key")
                    Text("Paste your key above, then click Save Key. Get a key at sunsethue.com/dev-api.")
                        .sunsetHueMuted()
                    HStack {
                        Button("Save Key") {
                            Task {
                                await appModel.saveAPIKey(appModel.apiKeyDraft)
                                if appModel.hasAPIKey {
                                    isReplacingAPIKey = false
                                }
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(appModel.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Test Connection") {
                            Task {
                                isTestingAccount = true
                                accountTestMessage = await appModel.testConnectionWithStoredOrDraftKey(
                                    appModel.apiKeyDraft.isEmpty ? nil : appModel.apiKeyDraft
                                )
                                isTestingAccount = false
                            }
                        }
                        .disabled(isTestingAccount)
                        if appModel.hasAPIKey {
                            Button("Cancel") {
                                isReplacingAPIKey = false
                                appModel.apiKeyDraft = ""
                            }
                        }
                    }
                }

                if let accountStatusMessage = appModel.accountStatusMessage {
                    Text(accountStatusMessage).font(.caption)
                }
                if let accountTestMessage {
                    Text(accountTestMessage).sunsetHueMuted()
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Remove API key?",
            isPresented: $confirmRemoveAPIKey,
            titleVisibility: .visible
        ) {
            Button("Remove Key", role: .destructive) {
                Task { await appModel.removeAPIKey() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SunsetHue will stop refreshing forecasts until you save a key again.")
        }
        .onAppear {
            appModel.refreshCredentialState()
            if appModel.credentialState != .configured {
                isAPIKeyFieldFocused = true
            }
        }
    }

    private var credentialStatusLabel: String {
        switch appModel.credentialState {
        case .unknown: return "Checking…"
        case .configured: return "Configured"
        case .missing: return "Not configured"
        case .unavailable: return "Keychain unavailable"
        }
    }

    private var credentialStatusTone: StatusTone {
        switch appModel.credentialState {
        case .unknown: return .neutral
        case .configured: return .positive
        case .missing: return .warning
        case .unavailable: return .negative
        }
    }

    private var updatesTab: some View {
        Form {
            Section {
                Toggle("Automatically check for updates once per day", isOn: $autoCheckUpdatesDaily)
                LabeledContent("Current version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                        ?? SunsetHueConstants.marketingVersion)
                }
                if let latestVersion {
                    LabeledContent("Latest known version") {
                        Text(latestVersion)
                    }
                }
            }
            Section {
                HStack {
                    Button(isCheckingUpdates ? "Checking…" : "Check Now") {
                        Task { await checkUpdates(force: true) }
                    }
                    .disabled(isCheckingUpdates)
                    Button("Open release page") {
                        NSWorkspace.shared.open(SunsetHueConstants.githubReleasesPageURL)
                    }
                }
                if let updateMessage {
                    Text(updateMessage)
                        .sunsetHueMuted()
                }
                Text("SunsetHue never downloads or replaces the app automatically.")
                    .sunsetHueMuted()
            }
        }
        .formStyle(.grouped)
    }

    private var diagnosticsTab: some View {
        Form {
            Section("Background Refresh") {
                let bg = appModel.backgroundRefreshDiagnostics()
                LabeledContent("Status") {
                    Text(bg.isActive ? "Active" : "Inactive")
                        .foregroundStyle(bg.isActive ? .primary : .secondary)
                }
                LabeledContent("Scheduler", value: bg.schedulerName)
                LabeledContent("Activity interval", value: bg.intervalDescription)
                LabeledContent("Last activity") {
                    if let last = bg.lastActivityAt {
                        Text(last.formatted(date: .omitted, time: .standard))
                    } else {
                        Text("None").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Last disposition") {
                    Text(bg.lastDisposition ?? "None")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Launch at Login") {
                    Text(bg.isLaunchAtLoginEnabled ? "On" : "Off")
                }
                Text("macOS controls background execution timing based on system power and activity conditions.")
                    .sunsetHueMuted()
            }

            Section("Storage & Shared Cache") {
                let storage = appModel.storageDiagnostics()
                LabeledContent("Storage mode", value: storage.storageModeDisplayName)
                if storage.isAppGroupAvailable {
                    LabeledContent("App Group", value: "Available")
                } else {
                    LabeledContent("App Group", value: "Local fallback")
                }
                LabeledContent("Shared settings file") {
                    Text(storage.isSettingsReadable ? "Readable" : "Unavailable")
                        .foregroundStyle(storage.isSettingsReadable ? .primary : .secondary)
                }
                LabeledContent("Shared forecast cache") {
                    Text(storage.isForecastCacheReadable ? "Readable" : "Unavailable")
                        .foregroundStyle(storage.isForecastCacheReadable ? .primary : .secondary)
                }
                LabeledContent("Last cache commit") {
                    if let commit = storage.lastCacheCommit {
                        Text(commit.formatted(date: .omitted, time: .standard))
                    } else {
                        Text("None").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Last reload requested") {
                    if let reload = storage.lastWidgetReloadRequested {
                        Text(reload.formatted(date: .omitted, time: .standard))
                    } else {
                        Text("None").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Locations (\(appModel.state.locations.count))") {
                let locations = appModel.locationDiagnostics()
                if locations.isEmpty {
                    Text("No locations configured.")
                        .sunsetHueMuted()
                } else {
                    ForEach(locations) { loc in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(loc.locationName)
                                    .font(.headline)
                                Spacer()
                                StatusBadge(
                                    title: loc.statusDisplayName,
                                    tone: tone(for: loc.status),
                                    accessibilityLabelText: "Location status",
                                    accessibilityValueText: loc.statusDisplayName
                                )
                            }
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                                GridRow {
                                    Text("Last success:").foregroundStyle(.secondary)
                                    Text(loc.lastSuccess.map { $0.formatted(date: .omitted, time: .shortened) } ?? "None")
                                    Text("Last attempt:").foregroundStyle(.secondary)
                                    Text(loc.lastAttempt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "None")
                                }
                                GridRow {
                                    Text("Next scheduled:").foregroundStyle(.secondary)
                                    Text(loc.nextScheduledRefresh.map { $0.formatted(date: .omitted, time: .shortened) } ?? "None")
                                    Text("Coverage:").foregroundStyle(.secondary)
                                    Text(loc.coverageDescription)
                                }
                                GridRow {
                                    Text("Refresh interval:").foregroundStyle(.secondary)
                                    Text("\(loc.refreshIntervalHours) hours")
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                        if loc.id != locations.last?.id {
                            Divider()
                        }
                    }
                }
            }

            Section("Recent Refresh Activity") {
                if recentActivities.isEmpty {
                    Text("No activity recorded yet.")
                        .sunsetHueMuted()
                } else {
                    ForEach(recentActivities.prefix(15)) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(entry.locationName)
                                        .font(.caption.weight(.medium))
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(entry.trigger.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.result.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(toneColor(for: entry.result))
                                if let details = entry.details, !details.isEmpty {
                                    Text(details)
                                        .font(.caption2)
                                        .sunsetHueMuted()
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Diagnostics Export & Actions") {
                Toggle("Include approximate coordinates (1 decimal place)", isOn: $includeApproximateCoordinates)
                Text("Even with coordinates redacted, a time zone can imply a broad geographic region.")
                    .sunsetHueMuted()
                HStack {
                    Button("Copy Diagnostics") {
                        Task {
                            diagnosticsMessage = await appModel.copyDiagnosticsToPasteboard(
                                includeApproximateCoordinates: includeApproximateCoordinates
                            )
                        }
                    }
                    Button("Export Diagnostics…") {
                        exportDiagnostics()
                    }
                    Button("Open Cache Folder") {
                        let url = AppSupportPaths.preferredContainerURL()
                        NSWorkspace.shared.open(url)
                    }
                }
                HStack {
                    Button("Open Privacy Policy…") {
                        if let url = URL(string: "https://github.com/andrewtryder/sunsethue-macos/blob/main/PRIVACY.md") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Refresh View") {
                        Task { recentActivities = await appModel.recentActivities() }
                    }
                }
                if let diagnosticsMessage {
                    Text(diagnosticsMessage)
                        .sunsetHueMuted()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func tone(for status: RefreshStatus) -> StatusTone {
        switch status {
        case .current: return .positive
        case .stale: return .neutral
        case .authenticationRequired: return .warning
        case .rateLimited: return .warning
        case .temporarilyUnavailable, .invalidResponse, .invalidRequest: return .negative
        }
    }

    private func toneColor(for result: RefreshResultSummary) -> Color {
        switch result {
        case .refreshedSuccessfully: return .green
        case .skippedFresh: return .secondary
        case .authenticationRequired, .rateLimited: return .orange
        case .transientFailure, .invalidRequest, .persistenceFailure: return .red
        }
    }

    private func maybeAutoCheckUpdates() async {
        guard autoCheckUpdatesDaily else { return }
        let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
        guard lastUpdateCheckDay != String(day) else { return }
        await checkUpdates(force: false)
        lastUpdateCheckDay = String(day)
    }

    private func checkUpdates(force: Bool) async {
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }
        do {
            let result = try await UpdateChecker().checkForUpdates()
            latestVersion = result.latestVersion
            if result.updateAvailable {
                updateMessage = "Update available: \(result.latestVersion ?? "newer version")."
                if force {
                    NSWorkspace.shared.open(result.releaseURL)
                }
            } else {
                updateMessage = "You are on the latest published version."
            }
        } catch {
            updateMessage = "Unable to check for updates right now."
        }
    }

    private func exportDiagnostics() {
        Task {
            var snapshots: [UUID: CachedLocationSnapshot] = [:]
            var cacheReadFailed = false
            for location in appModel.state.locations {
                do {
                    if let snapshot = try await appModel.forecastCache.loadSnapshot(for: location.id) {
                        snapshots[location.id] = snapshot
                    }
                } catch {
                    cacheReadFailed = true
                }
            }
            if cacheReadFailed && snapshots.isEmpty && !appModel.state.locations.isEmpty {
                diagnosticsMessage = "Cache could not be read."
                return
            }

            let exporter = DiagnosticsExporter()
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? SunsetHueConstants.marketingVersion
            let data: Data
            do {
                data = try exporter.makeReport(
                    state: appModel.state,
                    snapshots: snapshots,
                    apiKeyConfigured: appModel.hasAPIKey,
                    options: DiagnosticsExportOptions(includeApproximateCoordinates: includeApproximateCoordinates),
                    appVersion: version,
                    build: build,
                    notificationPreferences: appModel.notificationPreferences
                )
            } catch {
                diagnosticsMessage = "Report generation failed."
                return
            }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = "SunsetHue-diagnostics.json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                diagnosticsMessage = cacheReadFailed
                    ? "Export succeeded (some cache entries could not be read)."
                    : "Export succeeded."
            } catch {
                diagnosticsMessage = "File could not be written."
            }
        }
    }
}
