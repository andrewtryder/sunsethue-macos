import XCTest
@testable import SunsetHueCore

final class NotificationEvaluationTests: XCTestCase {
    private let timeZone = PreviewFixtures.sampleTimeZone
    private let locale = Locale(identifier: "en_US_POSIX")

    func testAfterSunriseSummarySelectsSunsetAndTomorrowSunrise() throws {
        let reference = fixedReferenceDate(hour: 12, minute: 0)
        let bundle = PreviewFixtures.sampleBundle(fetchedAt: reference)
        let sunrise = PreviewFixtures.averageSunrise(on: reference)
        let delivery = (sunrise.eventTime ?? reference).addingTimeInterval(60)
        let content = DailySummaryContentBuilder.content(
            location: PreviewFixtures.sampleLocation,
            bundle: bundle,
            deliveryDate: delivery,
            locale: locale
        )
        let body = try XCTUnwrap(content?.body)
        XCTAssertTrue(content?.title.contains("Sample Harbor") == true, content?.title ?? "")
        XCTAssertTrue(body.contains("Sunset"), body)
        XCTAssertTrue(body.lowercased().contains("tomorrow"), body)
        XCTAssertTrue(body.lowercased().contains("sunrise"), body)
    }

    func testAfterSunsetSummarySelectsTomorrowSunriseAndSunset() throws {
        let reference = fixedReferenceDate(hour: 12, minute: 0)
        let bundle = PreviewFixtures.sampleBundle(fetchedAt: reference)
        let sunset = PreviewFixtures.excellentSunset(on: reference)
        let delivery = (sunset.eventTime ?? reference).addingTimeInterval(60)
        let content = DailySummaryContentBuilder.content(
            location: PreviewFixtures.sampleLocation,
            bundle: bundle,
            deliveryDate: delivery,
            locale: locale
        )
        let body = try XCTUnwrap(content?.body).lowercased()
        XCTAssertTrue(body.contains("tomorrow"), body)
        XCTAssertTrue(body.contains("sunrise"), body)
        XCTAssertTrue(body.contains("sunset"), body)
    }

    func testDailyPlannerOneAndTwoSlots() {
        let location = PreviewFixtures.sampleLocation
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!

        let one = DailyNotificationSchedulePlanner.plans(
            location: location,
            rule: DailySummaryRule(enabled: true, firstTimeMinutes: 8 * 60, secondTimeEnabled: false),
            now: now,
            dayCount: 1
        )
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one.first?.slotNumber, 1)

        let two = DailyNotificationSchedulePlanner.plans(
            location: location,
            rule: DailySummaryRule(
                enabled: true,
                firstTimeMinutes: 8 * 60,
                secondTimeEnabled: true,
                secondTimeMinutes: 16 * 60
            ),
            now: now,
            dayCount: 1
        )
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two.map(\.slotNumber), [1, 2])
    }

    func testDailyPlannerUsesLocationTimeZoneNotHost() {
        let tokyo = SavedLocation(
            id: PreviewFixtures.sampleLocationID,
            name: "Tokyo",
            latitude: 35.68,
            longitude: 139.76,
            timeZoneIdentifier: "Asia/Tokyo",
            forecastDays: 2,
            includeSunrise: true,
            includeSunset: true,
            refreshIntervalHours: 6
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // Local 07:00 in Tokyo
        let now = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        let plans = DailyNotificationSchedulePlanner.plans(
            location: tokyo,
            rule: DailySummaryRule(enabled: true, firstTimeMinutes: 8 * 60),
            now: now,
            dayCount: 1
        )
        XCTAssertEqual(plans.count, 1)
        let components = DailyNotificationSchedulePlanner.dateComponents(
            for: plans[0],
            timeZone: tokyo.timeZone!
        )
        XCTAssertEqual(components.timeZone?.identifier, "Asia/Tokyo")
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 0)
    }

    func testDailyPlannerAcrossDSTSpringForward() {
        let location = PreviewFixtures.sampleLocation
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8
        components.hour = 7
        components.minute = 0
        components.timeZone = timeZone
        let now = Calendar(identifier: .gregorian).date(from: components)!
        let plans = DailyNotificationSchedulePlanner.plans(
            location: location,
            rule: DailySummaryRule(enabled: true, firstTimeMinutes: 8 * 60, secondTimeEnabled: false),
            now: now,
            dayCount: 2
        )
        XCTAssertFalse(plans.isEmpty)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        for plan in plans {
            XCTAssertEqual(calendar.component(.hour, from: plan.deliveryDate), 8)
        }
    }

    func testQualityThresholdBelowAtAndAbove() {
        let location = PreviewFixtures.sampleLocation
        let prefs = NotificationPreferences(
            notificationsEnabled: true,
            locationID: location.id,
            qualityAlert: QualityAlertRule(enabled: true, eventMode: .sunset, threshold: 0.70)
        )
        let below = snapshot(quality: 0.69, eventType: .sunset)
        XCTAssertTrue(
            QualityAlertEvaluator.candidates(
                location: location,
                snapshot: below,
                preferences: prefs,
                ledger: [],
                wasSuccessfulNetworkRefresh: true
            ).isEmpty
        )

        let at = snapshot(quality: 0.70, eventType: .sunset)
        XCTAssertEqual(
            QualityAlertEvaluator.candidates(
                location: location,
                snapshot: at,
                preferences: prefs,
                ledger: [],
                wasSuccessfulNetworkRefresh: true
            ).count,
            1
        )

        let above = snapshot(quality: 0.84, eventType: .sunset)
        XCTAssertEqual(
            QualityAlertEvaluator.candidates(
                location: location,
                snapshot: above,
                preferences: prefs,
                ledger: [],
                wasSuccessfulNetworkRefresh: true
            ).count,
            1
        )
    }

    func testMissingQualityNeverTriggers() {
        let location = PreviewFixtures.sampleLocation
        let prefs = NotificationPreferences(
            notificationsEnabled: true,
            locationID: location.id,
            qualityAlert: QualityAlertRule(enabled: true, threshold: 0.1)
        )
        let snap = CachedLocationSnapshot.fromSuccessful(
            bundle: LocationForecastBundle(
                locationID: location.id,
                fetchedAt: Date(),
                forecasts: [PreviewFixtures.missingModelQuality()]
            )
        )
        XCTAssertTrue(
            QualityAlertEvaluator.candidates(
                location: location,
                snapshot: snap,
                preferences: prefs,
                ledger: [],
                wasSuccessfulNetworkRefresh: true
            ).isEmpty
        )
    }

    func testCachedOrStaleRefreshNeverTriggers() {
        let location = PreviewFixtures.sampleLocation
        let prefs = NotificationPreferences(
            notificationsEnabled: true,
            locationID: location.id,
            qualityAlert: QualityAlertRule(enabled: true, threshold: 0.5)
        )
        let current = snapshot(quality: 0.9, eventType: .sunset)
        XCTAssertTrue(
            QualityAlertEvaluator.candidates(
                location: location,
                snapshot: current,
                preferences: prefs,
                ledger: [],
                wasSuccessfulNetworkRefresh: false
            ).isEmpty
        )

        let stale = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: Date(),
            lastAttemptAt: Date(),
            forecasts: current.forecasts,
            status: .stale,
            nextAttemptAt: nil,
            consecutiveFailureCount: 1
        )
        XCTAssertTrue(
            QualityAlertEvaluator.candidates(
                location: location,
                snapshot: stale,
                preferences: prefs,
                ledger: [],
                wasSuccessfulNetworkRefresh: true
            ).isEmpty
        )
    }

    func testOccurrenceNotifiedOnlyOnceAndDifferentDateAllowed() {
        let location = PreviewFixtures.sampleLocation
        let rule = QualityAlertRule(enabled: true, eventMode: .sunset, threshold: 0.5)
        let prefs = NotificationPreferences(
            notificationsEnabled: true,
            locationID: location.id,
            qualityAlert: rule
        )
        let first = snapshot(quality: 0.8, eventType: .sunset)
        let candidates = QualityAlertEvaluator.candidates(
            location: location,
            snapshot: first,
            preferences: prefs,
            ledger: [],
            wasSuccessfulNetworkRefresh: true
        )
        XCTAssertEqual(candidates.count, 1)
        let ledger = [NotificationLedgerEntry(key: candidates[0].key)]
        XCTAssertTrue(
            QualityAlertEvaluator.candidates(
                location: location,
                snapshot: first,
                preferences: prefs,
                ledger: ledger,
                wasSuccessfulNetworkRefresh: true
            ).isEmpty
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let nextDay = CachedLocationSnapshot.fromSuccessful(
            bundle: LocationForecastBundle(
                locationID: location.id,
                fetchedAt: Date(),
                forecasts: [
                    PreviewFixtures.qualityBandForecast(
                        quality: 0.8,
                        qualityText: "Excellent",
                        eventType: .sunset,
                        on: tomorrow
                    ).withForecastDate(tomorrow)
                ]
            )
        )
        XCTAssertEqual(
            QualityAlertEvaluator.candidates(
                location: location,
                snapshot: nextDay,
                preferences: prefs,
                ledger: ledger,
                wasSuccessfulNetworkRefresh: true
            ).count,
            1
        )
    }

    func testEditingRuleRevisionAllowsAgain() {
        let location = PreviewFixtures.sampleLocation
        var rule = QualityAlertRule(enabled: true, eventMode: .sunset, threshold: 0.5, revision: 1)
        let prefs = NotificationPreferences(
            notificationsEnabled: true,
            locationID: location.id,
            qualityAlert: rule
        )
        let snap = snapshot(quality: 0.8, eventType: .sunset)
        let first = QualityAlertEvaluator.candidates(
            location: location,
            snapshot: snap,
            preferences: prefs,
            ledger: [],
            wasSuccessfulNetworkRefresh: true
        )
        XCTAssertEqual(first.count, 1)

        rule.revision = 2
        rule.threshold = 0.6
        let revised = NotificationPreferences(
            notificationsEnabled: true,
            locationID: location.id,
            qualityAlert: rule
        )
        let again = QualityAlertEvaluator.candidates(
            location: location,
            snapshot: snap,
            preferences: revised,
            ledger: [NotificationLedgerEntry(key: first[0].key)],
            wasSuccessfulNetworkRefresh: true
        )
        XCTAssertEqual(again.count, 1)
        XCTAssertEqual(again[0].key.revision, 2)
    }

    func testDailyIdentifiersAreStableAndLocationScoped() {
        let location = PreviewFixtures.sampleLocation
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        let plans = DailyNotificationSchedulePlanner.plans(
            location: location,
            rule: DailySummaryRule(enabled: true, firstTimeMinutes: 8 * 60),
            now: now,
            dayCount: 1
        )
        XCTAssertEqual(plans.count, 1)
        XCTAssertTrue(DailyNotificationSchedulePlanner.isDailyIdentifier(plans[0].identifier))
        XCTAssertTrue(
            DailyNotificationSchedulePlanner.dailyIdentifierBelongs(
                to: location.id,
                identifier: plans[0].identifier
            )
        )
        XCTAssertFalse(
            DailyNotificationSchedulePlanner.dailyIdentifierBelongs(
                to: UUID(),
                identifier: plans[0].identifier
            )
        )
    }

    func testLedgerPruneRemovesOldEntries() {
        let key = NotificationOccurrenceKey(
            ruleID: UUID(),
            revision: 1,
            locationID: PreviewFixtures.sampleLocationID,
            eventType: .sunset,
            forecastDate: "2026-01-01"
        )
        let old = NotificationLedgerEntry(
            key: key,
            recordedAt: Date().addingTimeInterval(-10 * 86_400)
        )
        let recent = NotificationLedgerEntry(key: key, recordedAt: Date())
        let pruned = NotificationDeliveryLedgerMath.prune([old, recent])
        XCTAssertEqual(pruned.count, 1)
        XCTAssertEqual(pruned.first?.recordedAt, recent.recordedAt)
    }

    /// Noon America/New_York on a fixed winter day (no DST edge cases).
    private func fixedReferenceDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = hour
        components.minute = minute
        components.timeZone = timeZone
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func snapshot(quality: Double, eventType: EventType) -> CachedLocationSnapshot {
        CachedLocationSnapshot.fromSuccessful(
            bundle: LocationForecastBundle(
                locationID: PreviewFixtures.sampleLocationID,
                fetchedAt: Date(),
                forecasts: [
                    PreviewFixtures.qualityBandForecast(
                        quality: quality,
                        qualityText: quality >= 0.75 ? "Excellent" : "Good",
                        eventType: eventType
                    )
                ]
            )
        )
    }
}
