import XCTest
@testable import SunsetHueCore

final class MenuBarForecastResolverTests: XCTestCase {
    private let timeZone = PreviewFixtures.sampleTimeZone
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    private func location(
        sunrise: Bool = true,
        sunset: Bool = true
    ) -> SavedLocation {
        SavedLocation(
            id: PreviewFixtures.sampleLocationID,
            name: "Sandown",
            latitude: 42.9,
            longitude: -71.2,
            timeZoneIdentifier: timeZone.identifier,
            includeSunrise: sunrise,
            includeSunset: sunset
        )
    }

    private func snapshot(forecasts: [EventForecast], status: RefreshStatus = .current) -> CachedLocationSnapshot {
        CachedLocationSnapshot(
            locationID: PreviewFixtures.sampleLocationID,
            fetchedAt: Date(),
            lastAttemptAt: Date(),
            forecasts: forecasts,
            status: status
        )
    }

    func testBeforeSunriseSelectsSunrise() {
        let today = calendar.startOfDay(for: Date())
        let sunrise = PreviewFixtures.averageSunrise(on: today)
        let sunset = PreviewFixtures.excellentSunset(on: today)
        guard let sunriseTime = sunrise.eventTime else { return XCTFail("missing sunrise") }

        let item = MenuBarForecastResolver.resolve(
            location: location(),
            snapshot: snapshot(forecasts: [sunrise, sunset]),
            selection: .nextEvent,
            now: sunriseTime.addingTimeInterval(-60)
        )

        XCTAssertEqual(item?.eventType, .sunrise)
        XCTAssertEqual(item?.eventTime, sunriseTime)
    }

    func testBetweenSunriseAndSunsetSelectsSunset() {
        let today = calendar.startOfDay(for: Date())
        let sunrise = PreviewFixtures.averageSunrise(on: today)
        let sunset = PreviewFixtures.excellentSunset(on: today)
        guard let sunriseTime = sunrise.eventTime, let sunsetTime = sunset.eventTime else {
            return XCTFail("missing times")
        }

        let item = MenuBarForecastResolver.resolve(
            location: location(),
            snapshot: snapshot(forecasts: [sunrise, sunset]),
            selection: .nextEvent,
            now: sunriseTime.addingTimeInterval(60)
        )

        XCTAssertEqual(item?.eventType, .sunset)
        XCTAssertEqual(item?.eventTime, sunsetTime)
    }

    func testAfterSunsetSelectsTomorrowSunrise() {
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let sunrise = PreviewFixtures.averageSunrise(on: today)
        let sunset = PreviewFixtures.excellentSunset(on: today)
        let tomorrowSunrise = PreviewFixtures.averageSunrise(on: tomorrow).withForecastDate(tomorrow)
        guard let sunsetTime = sunset.eventTime else { return XCTFail("missing sunset") }

        let item = MenuBarForecastResolver.resolve(
            location: location(),
            snapshot: snapshot(forecasts: [sunrise, sunset, tomorrowSunrise]),
            selection: .nextEvent,
            now: sunsetTime.addingTimeInterval(60)
        )

        XCTAssertEqual(item?.eventType, .sunrise)
        XCTAssertEqual(item?.eventTime, tomorrowSunrise.eventTime)
    }

    func testNextSunsetSkipsSunrise() {
        let today = calendar.startOfDay(for: Date())
        let sunrise = PreviewFixtures.averageSunrise(on: today)
        let sunset = PreviewFixtures.excellentSunset(on: today)
        guard let sunriseTime = sunrise.eventTime else { return XCTFail("missing sunrise") }

        let item = MenuBarForecastResolver.resolve(
            location: location(),
            snapshot: snapshot(forecasts: [sunrise, sunset]),
            selection: .nextSunset,
            now: sunriseTime.addingTimeInterval(-60)
        )

        XCTAssertEqual(item?.eventType, .sunset)
    }

    func testNextSunriseSkipsSunset() {
        let today = calendar.startOfDay(for: Date())
        let sunrise = PreviewFixtures.averageSunrise(on: today)
        let sunset = PreviewFixtures.excellentSunset(on: today)
        guard let sunriseTime = sunrise.eventTime else { return XCTFail("missing sunrise") }

        let item = MenuBarForecastResolver.resolve(
            location: location(),
            snapshot: snapshot(forecasts: [sunrise, sunset]),
            selection: .nextSunrise,
            now: sunriseTime.addingTimeInterval(60)
        )

        XCTAssertNil(item)
    }

    func testNoFutureMatchingEventReturnsNil() {
        let today = calendar.startOfDay(for: Date())
        let sunrise = PreviewFixtures.averageSunrise(on: today)
        let sunset = PreviewFixtures.excellentSunset(on: today)
        guard let sunsetTime = sunset.eventTime else { return XCTFail("missing sunset") }

        let item = MenuBarForecastResolver.resolve(
            location: location(),
            snapshot: snapshot(forecasts: [sunrise, sunset]),
            selection: .nextEvent,
            now: sunsetTime.addingTimeInterval(60)
        )

        XCTAssertNil(item)
    }

    func testDisabledEventTypesAreRespected() {
        let today = calendar.startOfDay(for: Date())
        let sunrise = PreviewFixtures.averageSunrise(on: today)
        let sunset = PreviewFixtures.excellentSunset(on: today)
        guard let sunriseTime = sunrise.eventTime else { return XCTFail("missing sunrise") }

        let item = MenuBarForecastResolver.resolve(
            location: location(sunrise: true, sunset: false),
            snapshot: snapshot(forecasts: [sunrise, sunset]),
            selection: .nextSunset,
            now: sunriseTime.addingTimeInterval(-60)
        )

        XCTAssertNil(item)
        XCTAssertFalse(MenuBarForecastResolver.isSelectionEnabled(
            location: location(sunrise: true, sunset: false),
            selection: .nextSunset
        ))
    }
}

final class MenuBarRotationLogicTests: XCTestCase {
    private let timeZone = PreviewFixtures.sampleTimeZone

    private func makeLocation(id: UUID, name: String) -> SavedLocation {
        SavedLocation(
            id: id,
            name: name,
            latitude: 1,
            longitude: 2,
            timeZoneIdentifier: timeZone.identifier
        )
    }

    func testRotationFollowsLocationOrder() {
        let a = makeLocation(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, name: "A")
        let b = makeLocation(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, name: "B")
        let c = makeLocation(id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!, name: "C")
        let locations = [a, b, c]
        let prefs = MenuBarPreferences(locationMode: .rotateLocations, rotationIntervalSeconds: 10)
        let epoch = Date(timeIntervalSince1970: 0)

        let first = MenuBarRotationLogic.locationForLabel(
            locations: locations,
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: c.id,
            now: epoch.addingTimeInterval(5),
            epoch: epoch
        )
        let second = MenuBarRotationLogic.locationForLabel(
            locations: locations,
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: c.id,
            now: epoch.addingTimeInterval(15),
            epoch: epoch
        )

        XCTAssertEqual(first?.id, a.id)
        XCTAssertEqual(second?.id, b.id)
        // Rotation must not depend on selectedLocationID.
        XCTAssertNotEqual(first?.id, c.id)
    }

    func testRotationExcludesUnusableWhenUsableExist() {
        let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let usableID = UUID()
        let emptyID = UUID()
        let usable = makeLocation(id: usableID, name: "Usable")
        let empty = makeLocation(id: emptyID, name: "Empty")
        let sunset = PreviewFixtures.excellentSunset(on: today)
        let snapshot = CachedLocationSnapshot(
            locationID: usableID,
            fetchedAt: Date(),
            lastAttemptAt: Date(),
            forecasts: [sunset],
            status: .current
        )
        guard let sunsetTime = sunset.eventTime else { return XCTFail("missing sunset") }

        let candidates = MenuBarRotationLogic.rotationCandidates(
            locations: [empty, usable],
            snapshots: [usableID: snapshot],
            selection: .nextSunset,
            now: sunsetTime.addingTimeInterval(-120)
        )

        XCTAssertEqual(candidates.map(\.id), [usableID])
    }

    func testRemovingActiveRotatingLocationDoesNotCrash() {
        let a = makeLocation(id: UUID(), name: "A")
        let prefs = MenuBarPreferences(locationMode: .rotateLocations, rotationIntervalSeconds: 5)
        let location = MenuBarRotationLogic.locationForLabel(
            locations: [],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: a.id,
            now: Date()
        )
        XCTAssertNil(location)
    }

    func testSelectedLocationModeUsesSelection() {
        let a = makeLocation(id: UUID(), name: "A")
        let b = makeLocation(id: UUID(), name: "B")
        let prefs = MenuBarPreferences(locationMode: .selectedLocation)
        let selected = MenuBarRotationLogic.locationForLabel(
            locations: [a, b],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: b.id,
            now: Date()
        )
        XCTAssertEqual(selected?.id, b.id)
    }
}
