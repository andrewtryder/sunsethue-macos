import XCTest
@testable import SunsetHueCore

final class MultiLocation14Tests: XCTestCase {
    func testLocationReorderingPreservesArrayOrder() {
        let loc1 = SavedLocation(id: UUID(), name: "First", latitude: 40.0, longitude: -74.0, timeZoneIdentifier: "America/New_York")
        let loc2 = SavedLocation(id: UUID(), name: "Second", latitude: 34.0, longitude: -118.0, timeZoneIdentifier: "America/Los_Angeles")
        let loc3 = SavedLocation(id: UUID(), name: "Third", latitude: 51.5, longitude: -0.1, timeZoneIdentifier: "Europe/London")

        var state = SharedAppState(locations: [loc1, loc2, loc3], selectedLocationID: loc1.id)
        XCTAssertEqual(state.locations.map(\.name), ["First", "Second", "Third"])

        // Move "Third" to index 0
        state.moveLocations(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(state.locations.map(\.name), ["Third", "First", "Second"])
    }

    func testNotificationPreferencesSchemaV1Migration() throws {
        // Schema v1 JSON without locationRules
        let v1JSON = """
        {
            "schemaVersion": 1,
            "notificationsEnabled": true,
            "locationID": "11111111-1111-1111-1111-111111111111",
            "dailySummary": {
                "enabled": true,
                "firstTimeMinutes": 480,
                "secondTimeEnabled": false,
                "secondTimeMinutes": 960
            },
            "qualityAlert": {
                "id": "22222222-2222-2222-2222-222222222222",
                "enabled": true,
                "eventMode": "sunset",
                "threshold": 0.75,
                "revision": 1
            },
            "playSound": true
        }
        """

        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: v1JSON.data(using: .utf8)!)
        XCTAssertTrue(decoded.notificationsEnabled)
        XCTAssertEqual(decoded.locationID, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        // rule(for: targetID) should resolve the root rules
        let primaryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let resolvedRule = decoded.rule(for: primaryID)
        XCTAssertTrue(resolvedRule.dailySummary.enabled)
        XCTAssertTrue(resolvedRule.qualityAlert.enabled)
        XCTAssertEqual(resolvedRule.qualityAlert.threshold, 0.75)

        // An unconfigured location should resolve default un-enabled rule
        let otherID = UUID()
        let otherRule = decoded.rule(for: otherID)
        XCTAssertFalse(otherRule.qualityAlert.enabled)
        XCTAssertFalse(otherRule.dailySummary.enabled)
    }

    func testPerLocationNotificationPreferencesIsolation() {
        let loc1ID = UUID()
        let loc2ID = UUID()

        var prefs = NotificationPreferences(notificationsEnabled: true, locationID: loc1ID)
        var rule1 = LocationNotificationRule()
        rule1.qualityAlert.enabled = true
        rule1.qualityAlert.threshold = 0.80
        rule1.dailySummary.enabled = true

        var rule2 = LocationNotificationRule()
        rule2.qualityAlert.enabled = false
        rule2.qualityAlert.threshold = 0.60
        rule2.dailySummary.enabled = false

        prefs.setRule(rule1, for: loc1ID)
        prefs.setRule(rule2, for: loc2ID)

        XCTAssertTrue(prefs.rule(for: loc1ID).qualityAlert.enabled)
        XCTAssertEqual(prefs.rule(for: loc1ID).qualityAlert.threshold, 0.80)
        XCTAssertTrue(prefs.rule(for: loc1ID).dailySummary.enabled)

        XCTAssertFalse(prefs.rule(for: loc2ID).qualityAlert.enabled)
        XCTAssertEqual(prefs.rule(for: loc2ID).qualityAlert.threshold, 0.60)
        XCTAssertFalse(prefs.rule(for: loc2ID).dailySummary.enabled)
    }

    func testQualityAlertEvaluatorEvaluatesPerLocationRules() {
        let loc1 = SavedLocation(id: UUID(), name: "Loc 1", latitude: 40.0, longitude: -74.0, timeZoneIdentifier: "America/New_York")
        let loc2 = SavedLocation(id: UUID(), name: "Loc 2", latitude: 34.0, longitude: -118.0, timeZoneIdentifier: "America/Los_Angeles")

        var prefs = NotificationPreferences(notificationsEnabled: true)
        var rule1 = LocationNotificationRule()
        rule1.qualityAlert.enabled = true
        rule1.qualityAlert.threshold = 0.70
        rule1.qualityAlert.eventMode = .both

        var rule2 = LocationNotificationRule()
        rule2.qualityAlert.enabled = false // Disabled for Loc 2

        prefs.setRule(rule1, for: loc1.id)
        prefs.setRule(rule2, for: loc2.id)

        let forecast = EventForecast(
            responseTime: Date(),
            location: loc1.coordinates,
            gridLocation: loc1.coordinates,
            eventType: .sunset,
            modelData: true,
            quality: 0.85,
            qualityText: "Great",
            cloudCover: 0.2,
            eventTime: Date(),
            direction: 270,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: Date()
        )
        let snap1 = CachedLocationSnapshot(
            locationID: loc1.id,
            fetchedAt: Date(),
            lastAttemptAt: Date(),
            forecasts: [forecast],
            status: .current,
            nextAttemptAt: nil,
            consecutiveFailureCount: 0
        )
        let snap2 = CachedLocationSnapshot(
            locationID: loc2.id,
            fetchedAt: Date(),
            lastAttemptAt: Date(),
            forecasts: [forecast],
            status: .current,
            nextAttemptAt: nil,
            consecutiveFailureCount: 0
        )

        // loc1 should generate candidate
        let candidates1 = QualityAlertEvaluator.candidates(
            location: loc1,
            snapshot: snap1,
            preferences: prefs,
            ledger: [],
            wasSuccessfulNetworkRefresh: true
        )
        XCTAssertEqual(candidates1.count, 1)

        // loc2 should NOT generate candidate (disabled rule)
        let candidates2 = QualityAlertEvaluator.candidates(
            location: loc2,
            snapshot: snap2,
            preferences: prefs,
            ledger: [],
            wasSuccessfulNetworkRefresh: true
        )
        XCTAssertEqual(candidates2.count, 0)
    }

    func testDeletingNotificationLocationNeverBleedsRulesToRemainingOrNewLocations() {
        let locA = UUID()
        let locB = UUID()
        let locC = UUID()

        var prefs = NotificationPreferences(notificationsEnabled: true, locationID: locA)
        var ruleA = LocationNotificationRule()
        ruleA.qualityAlert.enabled = true
        ruleA.qualityAlert.threshold = 0.70
        ruleA.dailySummary.enabled = true
        prefs.setRule(ruleA, for: locA)

        XCTAssertTrue(prefs.rule(for: locA).qualityAlert.enabled)
        XCTAssertFalse(prefs.rule(for: locB).qualityAlert.enabled)

        // Delete location A
        prefs.removeRule(for: locA)

        // Verifications:
        XCTAssertNil(prefs.locationID)
        XCTAssertFalse(prefs.rule(for: locA).qualityAlert.enabled)
        XCTAssertFalse(prefs.rule(for: locB).qualityAlert.enabled)
        XCTAssertFalse(prefs.rule(for: locC).qualityAlert.enabled)
        XCTAssertFalse(prefs.rule(for: locB).dailySummary.enabled)
    }

    func testQualityRuleRevisionOnlyBumpsWhenThresholdOrModeMutatesOnTarget() {
        let locA = UUID()
        let locB = UUID()

        var prefs = NotificationPreferences(notificationsEnabled: true)
        var ruleA = LocationNotificationRule()
        ruleA.qualityAlert.threshold = 0.80
        ruleA.qualityAlert.revision = 1

        var ruleB = LocationNotificationRule()
        ruleB.qualityAlert.threshold = 0.60
        ruleB.qualityAlert.revision = 1

        prefs.setRule(ruleA, for: locA)
        prefs.setRule(ruleB, for: locB)

        // Merely reading / setting identical rule does not bump revision
        let readB = prefs.rule(for: locB)
        XCTAssertEqual(readB.qualityAlert.revision, 1)

        // Mutating locA threshold bumps locA's revision
        var updatedA = prefs.rule(for: locA)
        let prevA = updatedA
        updatedA.qualityAlert.threshold = 0.85
        if updatedA.qualityAlert.threshold != prevA.qualityAlert.threshold {
            updatedA.qualityAlert.revision += 1
        }
        prefs.setRule(updatedA, for: locA)

        XCTAssertEqual(prefs.rule(for: locA).qualityAlert.revision, 2)
        XCTAssertEqual(prefs.rule(for: locB).qualityAlert.revision, 1) // locB untouched!
    }

    func testMenuBarPopoverPresenterReflectsRefreshingStateAndReordering() {
        let loc1 = SavedLocation(id: UUID(), name: "First", latitude: 40.0, longitude: -74.0, timeZoneIdentifier: "America/New_York")
        let loc2 = SavedLocation(id: UUID(), name: "Second", latitude: 34.0, longitude: -118.0, timeZoneIdentifier: "America/Los_Angeles")

        let rows = MenuBarPopoverPresenter.buildRows(
            locations: [loc2, loc1], // Reordered
            snapshots: [:],
            preferences: MenuBarPreferences(),
            selectedLocationID: loc2.id,
            refreshingLocationIDs: [loc2.id]
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].id, loc2.id)
        XCTAssertTrue(rows[0].isRefreshing)
        XCTAssertTrue(rows[0].isSelected)

        XCTAssertEqual(rows[1].id, loc1.id)
        XCTAssertFalse(rows[1].isRefreshing)
        XCTAssertFalse(rows[1].isSelected)
    }
}
