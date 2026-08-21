import XCTest
@testable import SunsetHueCore

final class MultiDay15Tests: XCTestCase {
    func testBuildSectionsMatchesConfiguredForecastDays() {
        let loc = SavedLocation(
            id: UUID(),
            name: "Test Place",
            latitude: 40.7128,
            longitude: -74.0060,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 3,
            includeSunrise: true,
            includeSunset: true
        )

        let bundle = PreviewFixtures.sampleBundle(locationID: loc.id)
        let sections = MultiDayForecastPresenter.buildSections(location: loc, bundle: bundle)

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].dayLabel, "Today")
        XCTAssertEqual(sections[1].dayLabel, "Tomorrow")
        XCTAssertFalse(sections[2].dayLabel.isEmpty)
        XCTAssertNotEqual(sections[2].dayLabel, "Today")
        XCTAssertNotEqual(sections[2].dayLabel, "Tomorrow")

        XCTAssertNotNil(sections[0].sunrise)
        XCTAssertNotNil(sections[0].sunset)
    }

    func testBuildSectionsFiltersDisabledEvents() {
        let loc = SavedLocation(
            id: UUID(),
            name: "Sunset Only",
            latitude: 40.7128,
            longitude: -74.0060,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 2,
            includeSunrise: false,
            includeSunset: true
        )

        let bundle = PreviewFixtures.sampleBundle(locationID: loc.id)
        let sections = MultiDayForecastPresenter.buildSections(location: loc, bundle: bundle)

        XCTAssertEqual(sections.count, 2)
        XCTAssertNil(sections[0].sunrise)
        XCTAssertNotNil(sections[0].sunset)
        XCTAssertNil(sections[1].sunrise)
        XCTAssertNotNil(sections[1].sunset)
    }

    func testNextBestUpcomingEventPicksHighestQualityFutureEvent() {
        let loc = SavedLocation(
            id: UUID(),
            name: "Test Place",
            latitude: 40.7128,
            longitude: -74.0060,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 2,
            includeSunrise: true,
            includeSunset: true
        )

        let now = Date()
        let pastSunset = EventForecast(
            responseTime: now,
            location: loc.coordinates,
            gridLocation: loc.coordinates,
            eventType: .sunset,
            modelData: true,
            quality: 0.95,
            qualityText: "Great",
            cloudCover: 0.1,
            eventTime: now.addingTimeInterval(-3600), // Past
            direction: 270,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: now
        )

        let futureSunrise = EventForecast(
            responseTime: now,
            location: loc.coordinates,
            gridLocation: loc.coordinates,
            eventType: .sunrise,
            modelData: true,
            quality: 0.60,
            qualityText: "Fair",
            cloudCover: 0.4,
            eventTime: now.addingTimeInterval(3600), // Future (1 hr)
            direction: 90,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: now.addingTimeInterval(3600)
        )

        let futureSunset = EventForecast(
            responseTime: now,
            location: loc.coordinates,
            gridLocation: loc.coordinates,
            eventType: .sunset,
            modelData: true,
            quality: 0.85,
            qualityText: "Great",
            cloudCover: 0.2,
            eventTime: now.addingTimeInterval(7200), // Future (2 hr)
            direction: 270,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: now.addingTimeInterval(7200)
        )

        let bundle = LocationForecastBundle(
            locationID: loc.id,
            fetchedAt: now,
            forecasts: [pastSunset, futureSunrise, futureSunset]
        )

        let best = MultiDayForecastPresenter.nextBestUpcomingEvent(location: loc, bundle: bundle, now: now)
        XCTAssertNotNil(best)
        XCTAssertEqual(best?.eventType, .sunset)
        XCTAssertEqual(best?.quality, 0.85)
    }

    func testNextBestUpcomingEventReturnsNilWhenAllEventsInPast() {
        let loc = SavedLocation(
            id: UUID(),
            name: "Test Place",
            latitude: 40.7128,
            longitude: -74.0060,
            timeZoneIdentifier: "America/New_York"
        )

        let now = Date()
        let pastSunset = EventForecast(
            responseTime: now,
            location: loc.coordinates,
            gridLocation: loc.coordinates,
            eventType: .sunset,
            modelData: true,
            quality: 0.95,
            qualityText: "Great",
            cloudCover: 0.1,
            eventTime: now.addingTimeInterval(-3600),
            direction: 270,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: now
        )

        let bundle = LocationForecastBundle(
            locationID: loc.id,
            fetchedAt: now,
            forecasts: [pastSunset]
        )

        let best = MultiDayForecastPresenter.nextBestUpcomingEvent(location: loc, bundle: bundle, now: now)
        XCTAssertNil(best)
    }

    func testSingleDayDisplayHorizonDoesNotExposeTomorrowInOpportunityBanner() {
        let loc = SavedLocation(
            id: UUID(),
            name: "Single Day Place",
            latitude: 40.7128,
            longitude: -74.0060,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 1, // Only 1-day horizon!
            includeSunrise: true,
            includeSunset: true
        )

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 14, minute: 0))!
        let todaySunset = cal.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 19, minute: 30))!
        let tomorrowSunset = cal.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 19, minute: 30))!

        let fToday = EventForecast(
            responseTime: now,
            location: loc.coordinates,
            gridLocation: loc.coordinates,
            eventType: .sunset,
            modelData: true,
            quality: 0.60,
            qualityText: "Fair",
            cloudCover: 0.4,
            eventTime: todaySunset,
            direction: 270,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: now
        )

        let fTomorrow = EventForecast(
            responseTime: now,
            location: loc.coordinates,
            gridLocation: loc.coordinates,
            eventType: .sunset,
            modelData: true,
            quality: 0.95, // Higher quality, but in tomorrow's operational cache
            qualityText: "Excellent",
            cloudCover: 0.1,
            eventTime: tomorrowSunset,
            direction: 270,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: tomorrowSunset
        )

        let bundle = LocationForecastBundle(
            locationID: loc.id,
            fetchedAt: now,
            forecasts: [fToday, fTomorrow]
        )

        let best = MultiDayForecastPresenter.nextBestUpcomingEvent(location: loc, bundle: bundle, now: now)
        XCTAssertNotNil(best)
        // Must pick today's 0.60 quality, NOT tomorrow's 0.95 quality!
        XCTAssertEqual(best?.quality, 0.60)
        XCTAssertEqual(best?.eventTime, todaySunset)
    }

    func testEnabledEventWithMissingDataProducesUnavailableState() {
        let loc = SavedLocation(
            id: UUID(),
            name: "Both Enabled",
            latitude: 40.7128,
            longitude: -74.0060,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 1,
            includeSunrise: true,
            includeSunset: true
        )

        let now = Date()
        let sunsetOnly = EventForecast(
            responseTime: now,
            location: loc.coordinates,
            gridLocation: loc.coordinates,
            eventType: .sunset,
            modelData: true,
            quality: 0.80,
            qualityText: "Great",
            cloudCover: 0.2,
            eventTime: now.addingTimeInterval(3600),
            direction: 270,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: now
        )

        let bundle = LocationForecastBundle(
            locationID: loc.id,
            fetchedAt: now,
            forecasts: [sunsetOnly]
        )

        let sections = MultiDayForecastPresenter.buildSections(location: loc, bundle: bundle, now: now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].sunriseState, .unavailable(.sunrise))
        XCTAssertEqual(sections[0].sunsetState, .available(sunsetOnly))
    }

    func testRelativeDayLabelFormatting() {
        let tz = TimeZone(identifier: "America/New_York")!
        let ref = Date(timeIntervalSince1970: 1700000000)

        XCTAssertEqual(PresentationFormatting.relativeDayLabel(dayOffset: 0, reference: ref, timeZone: tz), "Today")
        XCTAssertEqual(PresentationFormatting.relativeDayLabel(dayOffset: 1, reference: ref, timeZone: tz), "Tomorrow")
        let day2 = PresentationFormatting.relativeDayLabel(dayOffset: 2, reference: ref, timeZone: tz)
        XCTAssertFalse(day2.isEmpty)
        XCTAssertNotEqual(day2, "Today")
        XCTAssertNotEqual(day2, "Tomorrow")
    }
}
