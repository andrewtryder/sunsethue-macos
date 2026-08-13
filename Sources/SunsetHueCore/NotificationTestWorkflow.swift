import Foundation

public struct NotificationTestResult: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case checkingSettings
        case requestingAuthorization
        case scheduled
        case confirmedPending
        case foregroundDelegateReceived
        case confirmedDelivered
        case suppressed
        case failed
    }

    public let stage: Stage
    public let message: String
    public let requestIdentifier: String?
    public let diagnostics: NotificationDiagnosticsSnapshot?

    public init(
        stage: Stage,
        message: String,
        requestIdentifier: String? = nil,
        diagnostics: NotificationDiagnosticsSnapshot? = nil
    ) {
        self.stage = stage
        self.message = message
        self.requestIdentifier = requestIdentifier
        self.diagnostics = diagnostics
    }
}

public struct NotificationDiagnosticsSnapshot: Equatable, Sendable, Codable {
    public var bundleIdentifier: String?
    public var executablePath: String?
    public var runningFromApplications: Bool
    public var teamIdentifierPresent: Bool
    public var teamIdentifier: String?
    public var authorizationStatus: String
    public var alertSetting: String
    public var notificationCenterSetting: String
    public var soundSetting: String
    public var lockScreenSetting: String
    public var testRequestPending: Bool?
    public var foregroundDelegateReceived: Bool?
    public var testRequestDelivered: Bool?
    public var lastTestStage: String?
    public var lastTestMessage: String?

    public init(
        bundleIdentifier: String?,
        executablePath: String?,
        runningFromApplications: Bool,
        teamIdentifierPresent: Bool,
        teamIdentifier: String?,
        authorizationStatus: String,
        alertSetting: String,
        notificationCenterSetting: String,
        soundSetting: String,
        lockScreenSetting: String,
        testRequestPending: Bool? = nil,
        foregroundDelegateReceived: Bool? = nil,
        testRequestDelivered: Bool? = nil,
        lastTestStage: String? = nil,
        lastTestMessage: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = executablePath
        self.runningFromApplications = runningFromApplications
        self.teamIdentifierPresent = teamIdentifierPresent
        self.teamIdentifier = teamIdentifier
        self.authorizationStatus = authorizationStatus
        self.alertSetting = alertSetting
        self.notificationCenterSetting = notificationCenterSetting
        self.soundSetting = soundSetting
        self.lockScreenSetting = lockScreenSetting
        self.testRequestPending = testRequestPending
        self.foregroundDelegateReceived = foregroundDelegateReceived
        self.testRequestDelivered = testRequestDelivered
        self.lastTestStage = lastTestStage
        self.lastTestMessage = lastTestMessage
    }

    public func copyText() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: self)
    }
}

public struct NotificationSettingsSnapshot: Equatable, Sendable {
    public enum AuthorizationStatus: String, Equatable, Sendable {
        case notDetermined
        case denied
        case authorized
        case provisional
        case ephemeral
        case unknown
    }

    public enum Setting: String, Equatable, Sendable {
        case enabled
        case disabled
        case notSupported
        case unknown
    }

    public var authorizationStatus: AuthorizationStatus
    public var alertSetting: Setting
    public var notificationCenterSetting: Setting
    public var soundSetting: Setting
    public var lockScreenSetting: Setting

    public init(
        authorizationStatus: AuthorizationStatus,
        alertSetting: Setting,
        notificationCenterSetting: Setting,
        soundSetting: Setting,
        lockScreenSetting: Setting
    ) {
        self.authorizationStatus = authorizationStatus
        self.alertSetting = alertSetting
        self.notificationCenterSetting = notificationCenterSetting
        self.soundSetting = soundSetting
        self.lockScreenSetting = lockScreenSetting
    }
}

public struct NotificationScheduleRequest: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var body: String
    public var userInfo: [String: String]
    public var playSound: Bool
    public var delaySeconds: TimeInterval

    public init(
        identifier: String,
        title: String,
        body: String,
        userInfo: [String: String],
        playSound: Bool,
        delaySeconds: TimeInterval
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.userInfo = userInfo
        self.playSound = playSound
        self.delaySeconds = delaySeconds
    }
}

public protocol NotificationCenterClienting: Sendable {
    func notificationSettings() async -> NotificationSettingsSnapshot
    func requestAuthorization() async throws -> Bool
    func add(_ request: NotificationScheduleRequest) async throws
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func removePending(withIdentifiers identifiers: [String]) async
    func removeDelivered(withIdentifiers identifiers: [String]) async
}

/// Progress callback for UI while a staged test runs.
public typealias NotificationTestProgressHandler = @Sendable (NotificationTestResult) -> Void

/// Staged test workflow that never treats `add` alone as delivery success.
public enum NotificationTestWorkflow: Sendable {
    public static let testIdentifierPrefix = "test."
    public static let foregroundPresentedNotification = Notification.Name("com.andrewtryder.SunsetHue.testNotificationPresented")

    public static func run(
        center: any NotificationCenterClienting,
        locationName: String,
        playSound: Bool,
        delaySeconds: TimeInterval = 3,
        onProgress: NotificationTestProgressHandler? = nil,
        waitForForeground: (@Sendable (String, TimeInterval) async -> Bool)? = nil,
        sleep: @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) async -> NotificationTestResult {
        func emit(_ result: NotificationTestResult) {
            onProgress?(result)
        }

        emit(NotificationTestResult(stage: .checkingSettings, message: "Checking notification settings…"))

        var settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .denied:
            let result = NotificationTestResult(
                stage: .failed,
                message: "Notification permission is denied."
            )
            emit(result)
            return result
        case .notDetermined:
            emit(NotificationTestResult(stage: .requestingAuthorization, message: "Requesting notification authorization…"))
            do {
                let granted = try await center.requestAuthorization()
                settings = await center.notificationSettings()
                if !granted || settings.authorizationStatus == .denied {
                    let result = NotificationTestResult(
                        stage: .failed,
                        message: "Notification permission is denied."
                    )
                    emit(result)
                    return result
                }
            } catch {
                let result = NotificationTestResult(
                    stage: .failed,
                    message: error.localizedDescription
                )
                emit(result)
                return result
            }
        case .authorized, .provisional, .ephemeral:
            break
        case .unknown:
            let result = NotificationTestResult(
                stage: .failed,
                message: "Unable to read notification authorization status."
            )
            emit(result)
            return result
        }

        if settings.alertSetting == .disabled {
            let result = NotificationTestResult(
                stage: .failed,
                message: "Notifications are allowed, but banners are disabled."
            )
            emit(result)
            return result
        }

        let pending = await center.pendingIdentifiers()
        let priorTests = pending.filter { $0.hasPrefix(Self.testIdentifierPrefix) }
        if !priorTests.isEmpty {
            await center.removePending(withIdentifiers: priorTests)
            await center.removeDelivered(withIdentifiers: priorTests)
        }

        let identifier = "\(Self.testIdentifierPrefix)\(UUID().uuidString)"
        let request = NotificationScheduleRequest(
            identifier: identifier,
            title: "SunsetHue test notification",
            body: "This is a test for \(locationName). Forecast alerts use the same local notification system.",
            userInfo: ["kind": "test"],
            playSound: playSound,
            delaySeconds: delaySeconds
        )

        do {
            try await center.add(request)
        } catch {
            let result = NotificationTestResult(
                stage: .failed,
                message: error.localizedDescription,
                requestIdentifier: identifier
            )
            emit(result)
            return result
        }

        emit(NotificationTestResult(
            stage: .scheduled,
            message: "Test notification scheduled — verifying pending queue…",
            requestIdentifier: identifier
        ))

        let pendingAfter = await center.pendingIdentifiers()
        guard pendingAfter.contains(identifier) else {
            let result = NotificationTestResult(
                stage: .failed,
                message: "The request never appeared in pending notifications.",
                requestIdentifier: identifier
            )
            emit(result)
            return result
        }

        emit(NotificationTestResult(
            stage: .confirmedPending,
            message: "Pending confirmation succeeded — waiting for delivery…",
            requestIdentifier: identifier
        ))

        let foregroundReceived: Bool
        if let waitForForeground {
            foregroundReceived = await waitForForeground(identifier, delaySeconds + 2)
            if foregroundReceived {
                emit(NotificationTestResult(
                    stage: .foregroundDelegateReceived,
                    message: "Foreground notification delegate received the test request.",
                    requestIdentifier: identifier
                ))
            }
        } else {
            await sleep(delaySeconds + 1)
            foregroundReceived = false
        }

        // Give Notification Center a moment to record delivered items.
        await sleep(0.75)

        let delivered = await center.deliveredIdentifiers()
        let wasDelivered = delivered.contains(identifier)

        if wasDelivered {
            let result = NotificationTestResult(
                stage: .confirmedDelivered,
                message: "Test notification delivered.",
                requestIdentifier: identifier
            )
            emit(result)
            return result
        }

        if foregroundReceived {
            let result = NotificationTestResult(
                stage: .foregroundDelegateReceived,
                message: "The foreground notification delegate was called, but the request was not found in delivered notifications.",
                requestIdentifier: identifier
            )
            emit(result)
            return result
        }

        if waitForForeground != nil {
            let result = NotificationTestResult(
                stage: .suppressed,
                message: "The request was scheduled but macOS suppressed the banner. Check Focus and SunsetHue notification banner settings.",
                requestIdentifier: identifier
            )
            emit(result)
            return result
        }

        let result = NotificationTestResult(
            stage: .suppressed,
            message: "The request was scheduled but macOS suppressed the banner. Check Focus and SunsetHue notification banner settings.",
            requestIdentifier: identifier
        )
        emit(result)
        return result
    }
}
