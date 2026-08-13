import XCTest
@testable import SunsetHueCore

actor FakeNotificationCenterClient: NotificationCenterClienting {
    var settings: NotificationSettingsSnapshot
    var grantAuthorization = true
    var pending: [String] = []
    var delivered: [String] = []
    var addError: Error?
    var addedRequests: [NotificationScheduleRequest] = []
    var removedPending: [[String]] = []
    var removedDelivered: [[String]] = []
    var clearPendingAfterAdd = false

    init(settings: NotificationSettingsSnapshot) {
        self.settings = settings
    }

    func notificationSettings() async -> NotificationSettingsSnapshot { settings }

    func requestAuthorization() async throws -> Bool {
        if grantAuthorization {
            settings.authorizationStatus = .authorized
        } else {
            settings.authorizationStatus = .denied
        }
        return grantAuthorization
    }

    func add(_ request: NotificationScheduleRequest) async throws {
        if let addError { throw addError }
        addedRequests.append(request)
        if clearPendingAfterAdd {
            return
        }
        pending.append(request.identifier)
    }

    func pendingIdentifiers() async -> [String] { pending }
    func deliveredIdentifiers() async -> [String] { delivered }

    func removePending(withIdentifiers identifiers: [String]) async {
        removedPending.append(identifiers)
        pending.removeAll { identifiers.contains($0) }
    }

    func removeDelivered(withIdentifiers identifiers: [String]) async {
        removedDelivered.append(identifiers)
        delivered.removeAll { identifiers.contains($0) }
    }

    func configure(
        clearPendingAfterAdd: Bool? = nil,
        addError: Error? = nil,
        pendingSeed: [String]? = nil
    ) {
        if let clearPendingAfterAdd { self.clearPendingAfterAdd = clearPendingAfterAdd }
        if let addError { self.addError = addError }
        if addError == nil, clearPendingAfterAdd == nil {
            // allow explicit nil clear of error via separate call
        }
        if addError == nil && clearPendingAfterAdd == nil && pendingSeed == nil {
            // no-op
        }
        if let pendingSeed { pending = pendingSeed }
        if clearPendingAfterAdd == nil, addError == nil {
            // keep
        }
    }

    func setClearPendingAfterAdd(_ value: Bool) { clearPendingAfterAdd = value }
    func setAddError(_ error: Error?) { addError = error }
    func seedPending(_ ids: [String]) { pending = ids }
    func markDelivered(_ id: String) {
        pending.removeAll { $0 == id }
        if !delivered.contains(id) { delivered.append(id) }
    }
}

final class NotificationTestWorkflowTests: XCTestCase {
    private func authorizedSettings(
        alert: NotificationSettingsSnapshot.Setting = .enabled
    ) -> NotificationSettingsSnapshot {
        NotificationSettingsSnapshot(
            authorizationStatus: .authorized,
            alertSetting: alert,
            notificationCenterSetting: .enabled,
            soundSetting: .enabled,
            lockScreenSetting: .enabled
        )
    }

    func testAuthorizationDenied() async {
        let center = FakeNotificationCenterClient(
            settings: NotificationSettingsSnapshot(
                authorizationStatus: .denied,
                alertSetting: .enabled,
                notificationCenterSetting: .enabled,
                soundSetting: .enabled,
                lockScreenSetting: .enabled
            )
        )
        let result = await NotificationTestWorkflow.run(
            center: center,
            locationName: "Sandown",
            playSound: false,
            delaySeconds: 0.01,
            sleep: { _ in }
        )
        XCTAssertEqual(result.stage, .failed)
        XCTAssertEqual(result.message, "Notification permission is denied.")
    }

    func testAlertPresentationDisabled() async {
        let center = FakeNotificationCenterClient(settings: authorizedSettings(alert: .disabled))
        let result = await NotificationTestWorkflow.run(
            center: center,
            locationName: "Sandown",
            playSound: true,
            delaySeconds: 0.01,
            sleep: { _ in }
        )
        XCTAssertEqual(result.stage, .failed)
        XCTAssertEqual(result.message, "Notifications are allowed, but banners are disabled.")
    }

    func testRequestAddedPendingAndDelivered() async {
        let center = FakeNotificationCenterClient(settings: authorizedSettings())
        let result = await NotificationTestWorkflow.run(
            center: center,
            locationName: "Sandown",
            playSound: false,
            delaySeconds: 0.01,
            waitForForeground: { id, _ in
                await center.markDelivered(id)
                return true
            },
            sleep: { _ in }
        )

        let added = await center.addedRequests
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(result.stage, .confirmedDelivered)
        XCTAssertEqual(result.message, "Test notification delivered.")
        XCTAssertNotNil(result.requestIdentifier)
    }

    func testPendingMissingFails() async {
        let center = FakeNotificationCenterClient(settings: authorizedSettings())
        await center.setClearPendingAfterAdd(true)

        let result = await NotificationTestWorkflow.run(
            center: center,
            locationName: "Sandown",
            playSound: false,
            delaySeconds: 0.01,
            sleep: { _ in }
        )
        XCTAssertEqual(result.stage, .failed)
        XCTAssertEqual(result.message, "The request never appeared in pending notifications.")
    }

    func testSuppressedWhenNotDelivered() async {
        let center = FakeNotificationCenterClient(settings: authorizedSettings())
        let result = await NotificationTestWorkflow.run(
            center: center,
            locationName: "Sandown",
            playSound: false,
            delaySeconds: 0.01,
            waitForForeground: { _, _ in false },
            sleep: { _ in }
        )
        XCTAssertEqual(result.stage, .suppressed)
        XCTAssertTrue(result.message.contains("suppressed"))
    }

    func testForegroundWithoutDeliveredReportsDelegateStage() async {
        let center = FakeNotificationCenterClient(settings: authorizedSettings())
        let result = await NotificationTestWorkflow.run(
            center: center,
            locationName: "Sandown",
            playSound: false,
            delaySeconds: 0.01,
            waitForForeground: { _, _ in true },
            sleep: { _ in }
        )
        XCTAssertEqual(result.stage, .foregroundDelegateReceived)
        XCTAssertTrue(result.message.contains("delegate"))
    }

    func testAddFailureIsSurfaced() async {
        struct Boom: LocalizedError {
            var errorDescription: String? { "add failed" }
        }
        let center = FakeNotificationCenterClient(settings: authorizedSettings())
        await center.setAddError(Boom())

        let result = await NotificationTestWorkflow.run(
            center: center,
            locationName: "Sandown",
            playSound: false,
            delaySeconds: 0.01,
            sleep: { _ in }
        )
        XCTAssertEqual(result.stage, .failed)
        XCTAssertEqual(result.message, "add failed")
    }

    func testOldTestRequestsAreRemoved() async {
        let center = FakeNotificationCenterClient(settings: authorizedSettings())
        await center.seedPending(["test.old-1", "daily.something"])

        _ = await NotificationTestWorkflow.run(
            center: center,
            locationName: "Sandown",
            playSound: false,
            delaySeconds: 0.01,
            waitForForeground: { id, _ in
                await center.markDelivered(id)
                return true
            },
            sleep: { _ in }
        )

        let removed = await center.removedPending
        XCTAssertTrue(removed.contains(where: { $0 == ["test.old-1"] || $0.contains("test.old-1") }))
        XCTAssertFalse(removed.contains(where: { $0.contains("daily.something") }))
    }

    func testTestNotificationsDoNotIncludeLocationID() async {
        let center = FakeNotificationCenterClient(settings: authorizedSettings())
        _ = await NotificationTestWorkflow.run(
            center: center,
            locationName: "Sandown",
            playSound: false,
            delaySeconds: 0.01,
            waitForForeground: { id, _ in
                await center.markDelivered(id)
                return true
            },
            sleep: { _ in }
        )
        let added = await center.addedRequests
        XCTAssertEqual(added.first?.userInfo["kind"], "test")
        XCTAssertNil(added.first?.userInfo["locationID"])
    }
}
