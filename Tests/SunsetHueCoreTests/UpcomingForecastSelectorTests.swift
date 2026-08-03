import XCTest
@testable import SunsetHueCore

final class UpcomingForecastSelectorTests: XCTestCase {
    private let timeZone = PreviewFixtures.sampleTimeZone

    func testOrdersFutureEventsChronologically() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let sunrise = PreviewFixtures.averageSunrise(on: today)
        let sunset = PreviewFixtures.excellentSunset(on: today)
        let tomorrowSunrise = PreviewFixtures.averageSunrise(on: tomorrow).withForecastDate(tomorrow)

        let bundle = LocationForecastBundle(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: Date(),
            forecasts: [sunset, tomorrowSunrise, sunrise]
        )

        // Between sunrise and sunset: next is sunset, then tomorrow sunrise.
        let now = (sunrise.eventTime ?? today).addingTimeInterval(60)
        let result = UpcomingForecastSelector.forecasts(
            from: bundle,
            allowedTypes: [.sunrise, .sunset],
            now: now,
            limit: 4
        )

        XCTAssertEqual(result.map(\.eventType), [.sunset, .sunrise])
        XCTAssertEqual(result.first?.eventTime, sunset.eventTime)
        XCTAssertEqual(result.last?.eventTime, tomorrowSunrise.eventTime)
    }

    func testExcludesEventAtExactNow() {
        let sunrise = PreviewFixtures.averageSunrise()
        let sunset = PreviewFixtures.excellentSunset()
        guard let sunriseTime = sunrise.eventTime else {
            return XCTFail("Fixture sunrise missing eventTime")
        }

        let bundle = LocationForecastBundle(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: Date(),
            forecasts: [sunrise, sunset]
        )

        let result = UpcomingForecastSelector.forecasts(
            from: bundle,
            allowedTypes: [.sunrise, .sunset],
            now: sunriseTime,
            limit: 4
        )

        XCTAssertEqual(result.map(\.eventType), [.sunset])
        XCTAssertFalse(result.contains { $0.eventType == .sunrise })
    }

    func testRespectsAllowedTypesAndLimit() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let bundle = LocationForecastBundle(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: Date(),
            forecasts: [
                PreviewFixtures.averageSunrise(on: today),
                PreviewFixtures.excellentSunset(on: today),
                PreviewFixtures.averageSunrise(on: tomorrow).withForecastDate(tomorrow),
                PreviewFixtures.excellentSunset(on: tomorrow).withForecastDate(tomorrow),
            ]
        )

        let now = today.addingTimeInterval(60)
        let sunrises = UpcomingForecastSelector.forecasts(
            from: bundle,
            allowedTypes: [.sunrise],
            now: now,
            limit: 1
        )

        XCTAssertEqual(sunrises.count, 1)
        XCTAssertEqual(sunrises.first?.eventType, .sunrise)
    }

    func testEmptyWhenAllEventsArePast() {
        let sunrise = PreviewFixtures.averageSunrise()
        let sunset = PreviewFixtures.excellentSunset()
        guard let sunsetTime = sunset.eventTime else {
            return XCTFail("Fixture sunset missing eventTime")
        }

        let bundle = LocationForecastBundle(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: Date(),
            forecasts: [sunrise, sunset]
        )

        let result = UpcomingForecastSelector.forecasts(
            from: bundle,
            allowedTypes: [.sunrise, .sunset],
            now: sunsetTime.addingTimeInterval(60),
            limit: 4
        )

        XCTAssertTrue(result.isEmpty)
    }
}
