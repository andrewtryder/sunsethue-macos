import XCTest
@testable import SunsetHueCore

/// In-memory stand-in for the system notification center.
actor FakeDailyNotificationCenter: DailyNotificationScheduling {
    private(set) var pending: [String: DailyNotificationDescriptor] = [:]
    private(set) var scheduleCalls: [String] = []
    private(set) var removeCalls: [[String]] = []
    private var failingIdentifiers: Set<String> = []
    private var gateOpen = true
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var listCount = 0

    init(pending: [DailyNotificationDescriptor] = []) {
        for descriptor in pending { self.pending[descriptor.identifier] = descriptor }
    }

    func failScheduling(for identifiers: Set<String>) { failingIdentifiers = identifiers }
    func closeGate() { gateOpen = false }
    func openGate() {
        gateOpen = true
        let waiters = gateWaiters
        gateWaiters = []
        waiters.forEach { $0.resume() }
    }

    func pendingDailyDescriptors() async -> [DailyNotificationDescriptor] {
        listCount += 1
        if !gateOpen {
            await withCheckedContinuation { gateWaiters.append($0) }
        }
        return Array(pending.values)
    }

    func schedule(_ descriptor: DailyNotificationDescriptor) async throws {
        scheduleCalls.append(descriptor.identifier)
        if failingIdentifiers.contains(descriptor.identifier) {
            throw SunsetHueError.networkUnavailable // any error
        }
        pending[descriptor.identifier] = descriptor
    }

    func removePending(identifiers: [String]) async {
        removeCalls.append(identifiers)
        for id in identifiers { pending.removeValue(forKey: id) }
    }

    func resetCallLog() {
        scheduleCalls = []
        removeCalls = []
    }

    func waitUntilListed(_ count: Int) async {
        for _ in 0..<400 where listCount < count {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

final class DailyNotificationReconcilerTests: XCTestCase {
    private let locationID = UUID()

    private func descriptor(
        _ id: String,
        body: String = "Body",
        hour: Int = 8,
        day: Int = 10,
        timeZone: String = "America/New_York"
    ) -> DailyNotificationDescriptor {
        DailyNotificationDescriptor(
            identifier: "daily.\(id)",
            locationID: locationID,
            title: "Title",
            body: body,
            playSound: true,
            year: 2026, month: 3, day: day, hour: hour, minute: 0,
            timeZoneIdentifier: timeZone
        )
    }

    // MARK: Pure reconciliation

    func testIdenticalPendingRequiresNoChanges() {
        let set = [descriptor("a"), descriptor("b")]
        let plan = DailyNotificationReconciler.reconcile(desired: set, pending: set)
        XCTAssertTrue(plan.toAdd.isEmpty)
        XCTAssertTrue(plan.toRemove.isEmpty)
    }

    func testChangedContentIsReplacedAndStaleIsRemoved() {
        let plan = DailyNotificationReconciler.reconcile(
            desired: [descriptor("a", body: "New"), descriptor("c")],
            pending: [descriptor("a", body: "Old"), descriptor("b")]
        )
        XCTAssertEqual(plan.toAdd.map(\.identifier), ["daily.a", "daily.c"])
        XCTAssertEqual(plan.toRemove, ["daily.b"])
    }

    func testChangedTimeZoneOrTimeIsReplaced() {
        let plan = DailyNotificationReconciler.reconcile(
            desired: [descriptor("a", timeZone: "Asia/Tokyo"), descriptor("b", hour: 9)],
            pending: [descriptor("a"), descriptor("b")]
        )
        XCTAssertEqual(plan.toAdd.map(\.identifier), ["daily.a", "daily.b"])
        XCTAssertTrue(plan.toRemove.isEmpty)
    }

    func testDuplicateDesiredIdentifiersScheduleOnce() {
        let plan = DailyNotificationReconciler.reconcile(
            desired: [descriptor("a", body: "first"), descriptor("a", body: "second")],
            pending: []
        )
        XCTAssertEqual(plan.toAdd.count, 1)
        XCTAssertEqual(plan.toAdd.first?.body, "second")
    }

    // MARK: Scheduler behaviour

    func testRescheduleWithUnchangedSetTouchesNothing() async {
        let center = FakeDailyNotificationCenter(pending: [descriptor("a"), descriptor("b")])
        let scheduler = DailyNotificationScheduler(scheduling: center)
        let result = await scheduler.apply(desired: [descriptor("a"), descriptor("b")])
        let scheduleCalls = await center.scheduleCalls
        let removeCalls = await center.removeCalls
        XCTAssertTrue(scheduleCalls.isEmpty)
        XCTAssertTrue(removeCalls.isEmpty)
        XCTAssertEqual(result.retained, 2)
        XCTAssertEqual(result.added, 0)
    }

    func testFailedSchedulingKeepsExistingValidNotifications() async {
        let center = FakeDailyNotificationCenter(pending: [descriptor("a", body: "Old"), descriptor("keep")])
        await center.failScheduling(for: ["daily.a"])
        let scheduler = DailyNotificationScheduler(scheduling: center)

        let result = await scheduler.apply(
            desired: [descriptor("a", body: "New"), descriptor("keep"), descriptor("new")]
        )

        XCTAssertEqual(result.failedIdentifiers, ["daily.a"])
        let pending = await center.pending
        XCTAssertEqual(pending["daily.a"]?.body, "Old", "Failed replacement must not delete the working request")
        XCTAssertNotNil(pending["daily.keep"])
        XCTAssertNotNil(pending["daily.new"], "Other schedules continue after one failure")
        let removeCalls = await center.removeCalls
        XCTAssertTrue(removeCalls.isEmpty)
    }

    func testDisablingRemovesAllPendingDailyNotifications() async {
        let center = FakeDailyNotificationCenter(pending: [descriptor("a"), descriptor("b")])
        let scheduler = DailyNotificationScheduler(scheduling: center)
        await scheduler.apply(desired: [])
        let pending = await center.pending
        XCTAssertTrue(pending.isEmpty)
    }

    func testConcurrentRequestsCoalesceAndLatestWins() async {
        let center = FakeDailyNotificationCenter()
        await center.closeGate()
        let scheduler = DailyNotificationScheduler(scheduling: center)

        let first = Task { await scheduler.apply(desired: [descriptor("a")]) }
        await center.waitUntilListed(1)          // first pass is now blocked mid-flight
        let second = Task { await scheduler.apply(desired: [descriptor("b")]) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let third = Task { await scheduler.apply(desired: [descriptor("c"), descriptor("d")]) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await center.openGate()

        _ = await first.value
        _ = await second.value
        _ = await third.value

        let pending = await center.pending
        XCTAssertEqual(Set(pending.keys), ["daily.c", "daily.d"], "Final state must equal the newest request")
        let calls = await center.scheduleCalls
        XCTAssertFalse(calls.contains("daily.b"), "Superseded request must never be applied")
        XCTAssertEqual(calls.count, Set(calls).count, "No identifier scheduled twice")
    }

    func testManyConcurrentIdenticalRequestsProduceNoDuplicates() async {
        let center = FakeDailyNotificationCenter()
        let scheduler = DailyNotificationScheduler(scheduling: center)
        let desired = (0..<5).map { descriptor("n\($0)") }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { await scheduler.apply(desired: desired) }
            }
        }
        let pending = await center.pending
        XCTAssertEqual(pending.count, 5)
        let calls = await center.scheduleCalls
        XCTAssertEqual(calls.count, 5, "Later passes see existing requests and schedule nothing")
    }

    // MARK: Descriptor building (per-location rules, time zones, DST)

    private func makeLocation(
        id: UUID = UUID(),
        timeZone: String,
        name: String = "Place"
    ) -> SavedLocation {
        SavedLocation(
            id: id,
            name: name,
            latitude: 40.0,
            longitude: -74.0,
            timeZoneIdentifier: timeZone,
            forecastDays: 2,
            includeSunrise: false,
            includeSunset: true,
            refreshIntervalHours: 6
        )
    }

    private func snapshot(for location: SavedLocation, around date: Date) -> CachedLocationSnapshot {
        var forecasts: [EventForecast] = []
        for offset in 0..<5 {
            let event = date.addingTimeInterval(TimeInterval(offset) * 86_400 + 43_200)
            forecasts.append(
                EventForecast(
                    responseTime: date,
                    location: location.coordinates,
                    gridLocation: location.coordinates,
                    eventType: .sunset,
                    modelData: true,
                    quality: 0.8,
                    qualityText: "Good",
                    cloudCover: 0.2,
                    eventTime: event,
                    direction: 270,
                    blueHour: nil,
                    goldenHour: nil,
                    forecastDate: date.addingTimeInterval(TimeInterval(offset) * 86_400)
                )
            )
        }
        return CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: date,
            lastAttemptAt: date,
            forecasts: forecasts,
            status: .current
        )
    }

    func testPerLocationRulesControlWhichLocationsGetNotifications() {
        let now = Date(timeIntervalSince1970: 1_772_000_000) // 2026-02-25
        let enabled = makeLocation(timeZone: "America/New_York", name: "On")
        let disabled = makeLocation(timeZone: "America/New_York", name: "Off")
        var prefs = NotificationPreferences(notificationsEnabled: true)
        var onRule = LocationNotificationRule()
        onRule.dailySummary.enabled = true
        prefs.locationRules[enabled.id] = onRule
        prefs.locationRules[disabled.id] = LocationNotificationRule()

        let state = SharedAppState(locations: [enabled, disabled])
        let snaps = [enabled.id: snapshot(for: enabled, around: now), disabled.id: snapshot(for: disabled, around: now)]
        let descriptors = DailyNotificationDescriptorBuilder.descriptors(
            state: state, snapshots: snaps, preferences: prefs, isAuthorized: true, now: now,
            locale: Locale(identifier: "en_US_POSIX")
        )
        XCTAssertFalse(descriptors.isEmpty)
        XCTAssertTrue(descriptors.allSatisfy { $0.locationID == enabled.id })

        let unauthorized = DailyNotificationDescriptorBuilder.descriptors(
            state: state, snapshots: snaps, preferences: prefs, isAuthorized: false, now: now
        )
        XCTAssertTrue(unauthorized.isEmpty)

        var masterOff = prefs
        masterOff.notificationsEnabled = false
        XCTAssertTrue(DailyNotificationDescriptorBuilder.descriptors(
            state: state, snapshots: snaps, preferences: masterOff, isAuthorized: true, now: now
        ).isEmpty)
    }

    func testSpringForwardAndFallBackKeepLocalWallClockTime() {
        let ny = makeLocation(timeZone: "America/New_York")
        let rule = DailySummaryRule(enabled: true, firstTimeMinutes: 8 * 60)

        // 2026-03-08 is spring-forward in the US; 2026-11-01 is fall-back.
        for (label, start, dayKey) in [
            ("spring", "2026-03-07T12:00:00Z", "2026-03-08"),
            ("fall", "2026-10-31T12:00:00Z", "2026-11-01"),
        ] {
            let now = ISO8601DateFormatter().date(from: start)!
            let plans = DailyNotificationSchedulePlanner.plans(location: ny, rule: rule, now: now, dayCount: 3)
            let transitionDay = plans.first { $0.identifier.contains(dayKey) }
            XCTAssertNotNil(transitionDay, label)
            guard let plan = transitionDay else { continue }
            let comps = DailyNotificationSchedulePlanner.dateComponents(for: plan, timeZone: ny.timeZone!)
            XCTAssertEqual(comps.hour, 8, "\(label): delivery stays 08:00 local")
            XCTAssertEqual(comps.minute, 0)
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = ny.timeZone!
            XCTAssertEqual(cal.component(.hour, from: plan.deliveryDate), 8, "\(label): absolute date resolves to 08:00 local")
        }
    }

    func testSameInstantYieldsDifferentLocalDaysAcrossTimeZones() {
        let now = ISO8601DateFormatter().date(from: "2026-06-15T20:00:00Z")! // Jun 16 05:00 Tokyo, Jun 15 13:00 LA
        let rule = DailySummaryRule(enabled: true, firstTimeMinutes: 8 * 60)
        let tokyo = makeLocation(timeZone: "Asia/Tokyo")
        let la = makeLocation(timeZone: "America/Los_Angeles")

        let tokyoFirst = DailyNotificationSchedulePlanner.plans(location: tokyo, rule: rule, now: now, dayCount: 2).first
        let laFirst = DailyNotificationSchedulePlanner.plans(location: la, rule: rule, now: now, dayCount: 2).first
        XCTAssertTrue(tokyoFirst?.identifier.hasSuffix("2026-06-16.1") ?? false, tokyoFirst?.identifier ?? "nil")
        XCTAssertTrue(laFirst?.identifier.hasSuffix("2026-06-16.1") ?? false, laFirst?.identifier ?? "nil")
        // LA's 08:00 on Jun 15 has already passed, so the first LA slot is the next morning.
        XCTAssertGreaterThan(laFirst!.deliveryDate, now)
        XCTAssertGreaterThan(tokyoFirst!.deliveryDate, now)
        XCTAssertLessThan(tokyoFirst!.deliveryDate, laFirst!.deliveryDate)
    }
}
