import XCTest
@testable import SunsetHueCore

final class LocationAndDateTests: XCTestCase {
    func testCoordinateValidation() {
        XCTAssertThrowsError(try Coordinates(latitude: 91, longitude: 0).validated())
        XCTAssertThrowsError(try Coordinates(latitude: 0, longitude: -181).validated())
        XCTAssertNoThrow(try Coordinates(latitude: -90, longitude: 180).validated())
    }

    func testDuplicateNormalizedLocations() {
        let first = SavedLocation(
            name: "A",
            latitude: 40.712801,
            longitude: -74.006001,
            timeZoneIdentifier: "America/New_York"
        )
        let second = SavedLocation(
            name: "B",
            latitude: 40.71280,
            longitude: -74.00600,
            timeZoneIdentifier: "America/New_York"
        )
        XCTAssertEqual(try first.validated().normalizedCoordinateKey, try second.validated().normalizedCoordinateKey)
        XCTAssertThrowsError(try second.validated(againstExisting: [try first.validated()])) { error in
            XCTAssertEqual(error as? SunsetHueError, .duplicateLocation)
        }
    }

    func testLocationRequiresSunriseOrSunset() {
        var location = SavedLocation(
            name: "X",
            latitude: 1,
            longitude: 2,
            timeZoneIdentifier: "UTC",
            includeSunrise: false,
            includeSunset: false
        )
        XCTAssertThrowsError(try location.validated())
        location.includeSunrise = true
        XCTAssertNoThrow(try location.validated())
    }

    func testDateGenerationAcrossLocalMidnight() {
        let calculator = ForecastDateCalculator()
        let tz = TimeZone(identifier: "America/New_York")!
        // 2026-03-08 23:30 America/New_York
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8
        components.hour = 23
        components.minute = 30
        components.timeZone = tz
        let now = Calendar(identifier: .gregorian).date(from: components)!
        let dates = calculator.localCalendarDates(dayCount: 3, timeZone: tz, now: now)
        XCTAssertEqual(dates.count, 3)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        XCTAssertEqual(cal.component(.day, from: dates[0]), 8)
        XCTAssertEqual(cal.component(.day, from: dates[1]), 9)
        XCTAssertEqual(cal.component(.day, from: dates[2]), 10)

        let midnight = calculator.nextMidnightRefresh(timeZone: tz, now: now)
        XCTAssertEqual(cal.component(.day, from: midnight), 9)
        XCTAssertEqual(cal.component(.second, from: midnight), SunsetHueConstants.midnightRefreshDelaySeconds)
    }

    func testDaylightSavingTimeBoundary() {
        let calculator = ForecastDateCalculator()
        let tz = TimeZone(identifier: "America/New_York")!
        // US DST spring forward 2026-03-08
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8
        components.hour = 1
        components.minute = 30
        components.timeZone = tz
        let now = Calendar(identifier: .gregorian).date(from: components)!
        let midnight = calculator.nextMidnightRefresh(timeZone: tz, now: now)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        XCTAssertEqual(cal.component(.month, from: midnight), 3)
        XCTAssertEqual(cal.component(.day, from: midnight), 9)
        XCTAssertEqual(cal.component(.hour, from: midnight), 0)
    }

    func testWidgetTimelineRefreshDateCalculation() {
        let calculator = ForecastDateCalculator()
        let tz = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reload = calculator.preferredTimelineReload(
            refreshIntervalHours: 6,
            timeZone: tz,
            now: now,
            rateLimitRetryAfter: nil,
            minimumIntervalSeconds: 15 * 60
        )
        XCTAssertGreaterThanOrEqual(reload.timeIntervalSince(now), 15 * 60)

        let rateLimited = calculator.preferredTimelineReload(
            refreshIntervalHours: 24,
            timeZone: tz,
            now: now,
            rateLimitRetryAfter: 30,
            minimumIntervalSeconds: 15 * 60
        )
        // Floor of 15 minutes wins over 30s retry.
        XCTAssertEqual(rateLimited.timeIntervalSince(now), 15 * 60, accuracy: 1)

        let id = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let jitter = SunsetHueConstants.timelineJitterSeconds(for: id)
        XCTAssertGreaterThanOrEqual(jitter, 0)
        XCTAssertLessThan(jitter, SunsetHueConstants.maxTimelineJitterSeconds)
        XCTAssertEqual(jitter, SunsetHueConstants.timelineJitterSeconds(for: id))
    }

    func testDeepLinkParsing() {
        let id = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let url = DeepLink.locationURL(id: id)
        XCTAssertEqual(DeepLink.parse(url), .location(id))
        XCTAssertEqual(DeepLink.parse(URL(string: "sunsethue://")!), .openApp)
    }
}
