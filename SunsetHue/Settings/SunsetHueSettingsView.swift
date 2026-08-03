import SwiftUI
import AppKit
import SunsetHueCore

struct SunsetHueSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
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
    @FocusState private var isAPIKeyFieldFocused: Bool

    private enum SettingsTab: String {
        case general
        case account
        case updates
        case privacy
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
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
                .tag(SettingsTab.updates)
            privacyTab
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)
            diagnosticsTab
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(SettingsTab.diagnostics)
        }
        .frame(width: 520, height: 480)
        .onAppear {
            launchAtLogin.refresh()
            Task { await maybeAutoCheckUpdates() }
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Show SunsetHue in menu bar", isOn: Binding(
                    get: { showMenuBarExtra },
                    set: { newValue in
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Open main window when launched", isOn: Binding(
                    get: { AppPreferenceDefaults.shared.openMainWindowOnLaunch },
                    set: { newValue in
                        if !newValue, !showMenuBarExtra, launchAtLogin.isEnabled {
                            launchAtLogin.errorMessage =
                                "Keep the menu bar icon or turn off Launch at Login before disabling the main window on launch."
                            return
                        }
                        AppPreferenceDefaults.shared.openMainWindowOnLaunch = newValue
                    }
                ))
            }
            Section("Defaults for new locations") {
                Stepper(
                    value: Binding(
                        get: { AppPreferenceDefaults.shared.defaultForecastDays },
                        set: { AppPreferenceDefaults.shared.defaultForecastDays = $0 }
                    ),
                    in: 1...3
                ) {
                    Text("Forecast days: \(AppPreferenceDefaults.shared.defaultForecastDays)")
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var accountTab: some View {
        Form {
            Section("API key") {
                LabeledContent("Status") {
                    Text(credentialStatusLabel)
                        .foregroundStyle(appModel.credentialState == .configured ? Color.secondary : Color.orange)
                }
                SecureField("Paste your SunsetHue API key", text: $appModel.apiKeyDraft)
                    .focused($isAPIKeyFieldFocused)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("API key")
                Text("Paste your key above, then click Save Key. Get a key at sunsethue.com/dev-api.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save Key") {
                        Task { await appModel.saveAPIKey(appModel.apiKeyDraft) }
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
                    Button("Remove Key", role: .destructive) {
                        Task { await appModel.removeAPIKey() }
                    }
                    .disabled(!appModel.hasAPIKey)
                }
                if let accountStatusMessage = appModel.accountStatusMessage {
                    Text(accountStatusMessage).font(.caption)
                }
                if let accountTestMessage {
                    Text(accountTestMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
        case .unavailable: return "Keychain unavailable — unlock your Mac"
        }
    }

    private var updatesTab: some View {
        Form {
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
            Button(isCheckingUpdates ? "Checking…" : "Check Now") {
                Task { await checkUpdates(force: true) }
            }
            .disabled(isCheckingUpdates)
            Button("Open release page") {
                NSWorkspace.shared.open(SunsetHueConstants.githubReleasesPageURL)
            }
            if let updateMessage {
                Text(updateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("SunsetHue never downloads or replaces the app automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var privacyTab: some View {
        ScrollView {
            Text(PrivacyStatement.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private var diagnosticsTab: some View {
        Form {
            Toggle("Include approximate coordinates (1 decimal place)", isOn: $includeApproximateCoordinates)
            Text("Even with coordinates redacted, a time zone can imply a broad geographic region.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Export Diagnostics…") {
                exportDiagnostics()
            }
            if let diagnosticsMessage {
                Text(diagnosticsMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Open cache folder") {
                let url = AppSupportPaths.preferredContainerURL()
                NSWorkspace.shared.open(url)
            }
            Button("Copy version information") {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? SunsetHueConstants.marketingVersion
                let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("SunsetHue \(version) (\(build))", forType: .string)
            }
        }
        .formStyle(.grouped)
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
                    build: build
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

enum PrivacyStatement {
    static let text = """
    SunsetHue sends the configured latitude, longitude, forecast date, event type, and API key to api.sunsethue.com over HTTPS when retrieving a forecast. The API key is stored in the macOS Keychain. Forecast data and application preferences are stored locally.

    Location Services is accessed only when you select “Use Current Location.” SunsetHue does not continuously monitor your location.

    When update checking is enabled or “Check Now” is selected, SunsetHue contacts GitHub’s API to determine the latest published version.

    SunsetHue contains no analytics, advertising, tracking, telemetry, or third-party crash-reporting service.

    The widget does not access the API key or contact SunsetHue directly. It reads sanitized forecast information stored locally by the main application.

    Diagnostic exports exclude the API key and exact coordinates by default.
    """
}
