import XCTest
@testable import SunsetHueCore

final class MenuBarPopoverPresenterTests: XCTestCase {
    private let timeZone = PreviewFixtures.sampleTimeZone
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    private func makeLocation(
        id: UUID = UUID(),
        name: String,
        sunrise: Bool = true,
        sunset: Bool = true
    ) -> SavedLocation {
        SavedLocation(
            id: id,
            name: name,
            latitude: 40.7128,
            longitude: -74.006,
            timeZoneIdentifier: timeZone.identifier,
            includeSunrise: sunrise,
            includeSunset: sunset
        )
    }

    private func makeSnapshot(
        locationID: UUID,
        forecasts: [EventForecast],
        status: RefreshStatus = .current
    ) -> CachedLocationSnapshot {
        CachedLocationSnapshot(
            locationID: locationID,
            fetchedAt: Date(),
            lastAttemptAt: Date(),
            forecasts: forecasts,
            status: status
        )
    }

    // 1. One row is generated per configured location.
    func testOneRowPerConfiguredLocation() {
        let loc1 = makeLocation(name: "New York")
        let loc2 = makeLocation(name: "Los Angeles")
        let loc3 = makeLocation(name: "London")
        let prefs = MenuBarPreferences()

        let emptyRows = MenuBarPopoverPresenter.buildRows(
            locations: [],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: nil,
            now: Date()
        )
        XCTAssertEqual(emptyRows.count, 0)

        let rows = MenuBarPopoverPresenter.buildRows(
            locations: [loc1, loc2, loc3],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: loc1.id,
            now: Date()
        )
        XCTAssertEqual(rows.count, 3)
    }

    // 2. Configured location order is preserved.
    func testConfiguredLocationOrderIsPreserved() {
        let loc1 = makeLocation(name: "First")
        let loc2 = makeLocation(name: "Second")
        let loc3 = makeLocation(name: "Third")
        let locations = [loc1, loc2, loc3]
        let prefs = MenuBarPreferences()

        let rows = MenuBarPopoverPresenter.buildRows(
            locations: locations,
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: loc2.id,
            now: Date()
        )

        XCTAssertEqual(rows.map(\.id), [loc1.id, loc2.id, loc3.id])
        XCTAssertEqual(rows.map(\.name), ["First", "Second", "Third"])
    }

    // 3. nextEvent independently resolves sunrise/sunset for each location.
    func testNextEventIndependentlyResolvesForLocations() {
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let locA = makeLocation(name: "Location A")
        let locB = makeLocation(name: "Location B")

        let sunsetA = PreviewFixtures.excellentSunset(on: today)
        guard let sunsetTimeA = sunsetA.eventTime else { return XCTFail("missing sunset time") }
        let sunriseB = PreviewFixtures.averageSunrise(on: tomorrow).withForecastDate(tomorrow)
        guard let sunriseTimeB = sunriseB.eventTime else { return XCTFail("missing sunrise time") }

        // locA has upcoming sunset today
        let snapA = makeSnapshot(locationID: locA.id, forecasts: [sunsetA])
        // locB has upcoming sunrise tomorrow
        let snapB = makeSnapshot(locationID: locB.id, forecasts: [sunriseB])

        let now = sunsetTimeA.addingTimeInterval(-3600)

        let rows = MenuBarPopoverPresenter.buildRows(
            locations: [locA, locB],
            snapshots: [locA.id: snapA, locB.id: snapB],
            preferences: MenuBarPreferences(eventSelection: .nextEvent),
            selectedLocationID: locA.id,
            now: now
        )

        XCTAssertEqual(rows[0].eventType, .sunset)
        XCTAssertEqual(rows[0].eventLabel, "Sunset")
        XCTAssertEqual(rows[1].eventType, .sunrise)
        XCTAssertEqual(rows[1].eventLabel, "Sunrise")
        _ = sunriseTimeB
    }

    // 4. Today event formatting does not unnecessarily prefix "Today".
    func testTodayEventFormattingDoesNotPrefixToday() {
        let today = calendar.startOfDay(for: Date())
        let sunset = PreviewFixtures.excellentSunset(on: today)
        guard let sunsetTime = sunset.eventTime else { return XCTFail("missing sunset time") }

        let loc = makeLocation(name: "New York")
        let snap = makeSnapshot(locationID: loc.id, forecasts: [sunset])
        let now = sunsetTime.addingTimeInterval(-1800)

        let row = MenuBarPopoverPresenter.row(
            for: loc,
            snapshot: snap,
            preferences: MenuBarPreferences(),
            isSelected: true,
            now: now
        )

        guard let dayTimeLabel = row.dayTimeLabel else { return XCTFail("missing dayTimeLabel") }
        XCTAssertFalse(dayTimeLabel.contains("Today"))
        let expectedTime = PresentationFormatting.timeString(sunsetTime, timeZone: timeZone)
        XCTAssertEqual(dayTimeLabel, expectedTime)
    }

    // 5. Tomorrow/future events are clearly identified.
    func testTomorrowAndFutureEventsAreClearlyIdentified() {
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today)!

        let sunriseTomorrow = PreviewFixtures.averageSunrise(on: tomorrow).withForecastDate(tomorrow)
        let sunsetDayAfter = PreviewFixtures.excellentSunset(on: dayAfterTomorrow).withForecastDate(dayAfterTomorrow)

        guard let timeTomorrow = sunriseTomorrow.eventTime, let timeDayAfter = sunsetDayAfter.eventTime else {
            return XCTFail("missing times")
        }

        let loc1 = makeLocation(name: "Tomorrow Loc")
        let snap1 = makeSnapshot(locationID: loc1.id, forecasts: [sunriseTomorrow])

        let loc2 = makeLocation(name: "Future Loc")
        let snap2 = makeSnapshot(locationID: loc2.id, forecasts: [sunsetDayAfter])

        let now = today.addingTimeInterval(3600 * 12)

        let row1 = MenuBarPopoverPresenter.row(
            for: loc1,
            snapshot: snap1,
            preferences: MenuBarPreferences(),
            isSelected: false,
            now: now
        )
        let row2 = MenuBarPopoverPresenter.row(
            for: loc2,
            snapshot: snap2,
            preferences: MenuBarPreferences(),
            isSelected: false,
            now: now
        )

        XCTAssertTrue(row1.dayTimeLabel?.hasPrefix("Tomorrow ") == true)
        let shortFormatter = DateFormatter()
        shortFormatter.timeZone = timeZone
        shortFormatter.setLocalizedDateFormatFromTemplate("EEE")
        let dayName = shortFormatter.string(from: timeDayAfter)
        XCTAssertTrue(row2.dayTimeLabel?.hasPrefix("\(dayName) ") == true)
        _ = timeTomorrow
    }

    // 6. Long/unavailable/error states produce concise fallback presentation data.
    func testUnavailableAndErrorStatesProduceConciseFallbackData() {
        let loc = makeLocation(name: "City")
        let prefs = MenuBarPreferences()

        let authSnap = makeSnapshot(locationID: loc.id, forecasts: [], status: .authenticationRequired)
        let authRow = MenuBarPopoverPresenter.row(for: loc, snapshot: authSnap, preferences: prefs, isSelected: false)
        XCTAssertEqual(authRow.statusMessage, "API key needed")
        XCTAssertEqual(authRow.statusSymbolName, "key.slash")
        XCTAssertNil(authRow.eventType)
        XCTAssertNil(authRow.qualityLabel)

        let rateSnap = makeSnapshot(locationID: loc.id, forecasts: [], status: .rateLimited(retryAfter: nil))
        let rateRow = MenuBarPopoverPresenter.row(for: loc, snapshot: rateSnap, preferences: prefs, isSelected: false)
        XCTAssertEqual(rateRow.statusMessage, "Rate limited")
        XCTAssertEqual(rateRow.statusSymbolName, "clock.badge.exclamationmark")

        let tempSnap = makeSnapshot(locationID: loc.id, forecasts: [], status: .temporarilyUnavailable)
        let tempRow = MenuBarPopoverPresenter.row(for: loc, snapshot: tempSnap, preferences: prefs, isSelected: false)
        XCTAssertEqual(tempRow.statusMessage, "Temporarily unavailable")
        XCTAssertEqual(tempRow.statusSymbolName, "exclamationmark.triangle")

        let invalidReqSnap = makeSnapshot(locationID: loc.id, forecasts: [], status: .invalidRequest)
        let invalidReqRow = MenuBarPopoverPresenter.row(for: loc, snapshot: invalidReqSnap, preferences: prefs, isSelected: false)
        XCTAssertEqual(invalidReqRow.statusMessage, "Invalid location")

        let invalidRespSnap = makeSnapshot(locationID: loc.id, forecasts: [], status: .invalidResponse)
        let invalidRespRow = MenuBarPopoverPresenter.row(for: loc, snapshot: invalidRespSnap, preferences: prefs, isSelected: false)
        XCTAssertEqual(invalidRespRow.statusMessage, "Incompatible response")

        let staleSnap = makeSnapshot(locationID: loc.id, forecasts: [], status: .stale)
        let staleRow = MenuBarPopoverPresenter.row(for: loc, snapshot: staleSnap, preferences: prefs, isSelected: false)
        XCTAssertEqual(staleRow.statusMessage, "Forecast stale")
        XCTAssertEqual(staleRow.statusSymbolName, "arrow.clockwise")

        let nilSnapRow = MenuBarPopoverPresenter.row(for: loc, snapshot: nil, preferences: prefs, isSelected: false)
        XCTAssertEqual(nilSnapRow.statusMessage, "No forecast available")
        XCTAssertEqual(nilSnapRow.statusSymbolName, "minus.circle")

        let disabledSunsetLoc = makeLocation(name: "NoSunset", sunrise: true, sunset: false)
        let disabledRow = MenuBarPopoverPresenter.row(
            for: disabledSunsetLoc,
            snapshot: nil,
            preferences: MenuBarPreferences(eventSelection: .nextSunset),
            isSelected: false
        )
        XCTAssertEqual(disabledRow.statusMessage, "Sunset disabled")
        XCTAssertEqual(disabledRow.statusSymbolName, "slash.circle")
    }

    // 7. Selected location is identified correctly.
    func testSelectedLocationIsIdentifiedCorrectly() {
        let loc1 = makeLocation(name: "A")
        let loc2 = makeLocation(name: "B")
        let prefs = MenuBarPreferences()

        let rows1 = MenuBarPopoverPresenter.buildRows(
            locations: [loc1, loc2],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: loc2.id,
            now: Date()
        )
        XCTAssertFalse(rows1[0].isSelected)
        XCTAssertTrue(rows1[1].isSelected)

        // Fallback when selectedLocationID is nil selects the first location
        let rows2 = MenuBarPopoverPresenter.buildRows(
            locations: [loc1, loc2],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: nil,
            now: Date()
        )
        XCTAssertTrue(rows2[0].isSelected)
        XCTAssertFalse(rows2[1].isSelected)
    }

    // 8. Quality values format consistently.
    func testQualityValuesFormatConsistently() {
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 0.82), "82%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 0.91), "91%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 0.67), "67%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 0.0), "0%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 1.0), "100%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: nil), "—")
    }

    // 9. Permanent menu-bar label resolves the selected location correctly.
    func testPermanentMenuBarLabelResolvesSelectedLocation() {
        let loc1 = makeLocation(name: "A")
        let loc2 = makeLocation(name: "B")
        let prefs = MenuBarPreferences(locationMode: .selectedLocation)

        let selected = MenuBarRotationLogic.locationForLabel(
            locations: [loc1, loc2],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: loc2.id,
            now: Date()
        )
        XCTAssertEqual(selected?.id, loc2.id)
    }

    // 10. Single location produces exactly one row.
    func testSingleConfiguredLocationProducesExactlyOneRow() {
        let loc = makeLocation(name: "Single Location")
        let prefs = MenuBarPreferences()

        let rows = MenuBarPopoverPresenter.buildRows(
            locations: [loc],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: loc.id,
            now: Date()
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "Single Location")
        XCTAssertTrue(rows.first?.isSelected == true)
    }

    // 11. Five configured locations produce exactly five rows.
    func testFiveConfiguredLocationsProduceFiveRows() {
        let names = ["New York", "Los Angeles", "Chicago", "Houston", "Phoenix"]
        let locations = names.map { makeLocation(name: $0) }
        let prefs = MenuBarPreferences()

        let rows = MenuBarPopoverPresenter.buildRows(
            locations: locations,
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: locations[2].id,
            now: Date()
        )

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map(\.name), names)
        XCTAssertEqual(rows.filter(\.isSelected).count, 1)
        XCTAssertEqual(rows.first(where: \.isSelected)?.name, "Chicago")
    }

    // 12. Extremely long location names remain intact in the presentation model.
    func testLongLocationNamePreservedInModel() {
        let longName = "Washington, District of Columbia, United States of America"
        let loc = makeLocation(name: longName)
        let prefs = MenuBarPreferences()

        let rows = MenuBarPopoverPresenter.buildRows(
            locations: [loc],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: loc.id,
            now: Date()
        )

        XCTAssertEqual(rows.first?.name, longName)
    }

    // 13. Every presenter row is defensive and never logically blank.
    func testPresenterNeverGeneratesLogicallyBlankRow() {
        let today = calendar.startOfDay(for: Date())
        let sunset = PreviewFixtures.excellentSunset(on: today)
        guard let sunsetTime = sunset.eventTime else { return XCTFail("missing sunset time") }

        let loc1 = makeLocation(name: "With Forecast")
        let snap1 = makeSnapshot(locationID: loc1.id, forecasts: [sunset])

        let loc2 = makeLocation(name: "Without Snapshot")

        let loc3 = makeLocation(name: "With Error Status")
        let snap3 = makeSnapshot(locationID: loc3.id, forecasts: [], status: .temporarilyUnavailable)

        let prefs = MenuBarPreferences()
        let rows = MenuBarPopoverPresenter.buildRows(
            locations: [loc1, loc2, loc3],
            snapshots: [loc1.id: snap1, loc3.id: snap3],
            preferences: prefs,
            selectedLocationID: loc1.id,
            now: sunsetTime.addingTimeInterval(-1800)
        )

        for row in rows {
            let hasForecastFields = (row.eventType != nil && row.eventLabel != nil && row.dayTimeLabel != nil && row.qualityLabel != nil)
            let hasStatusMessage = (row.statusMessage != nil && row.statusMessage?.isEmpty == false)
            XCTAssertTrue(
                hasForecastFields || hasStatusMessage,
                "Row '\(row.name)' must either have complete forecast fields or a non-empty status message"
            )
        }
    }
}
