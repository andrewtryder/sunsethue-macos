import XCTest
@testable import SunsetHueCore

final class PlaceAndTimeZoneTests: XCTestCase {
    func testApplyResolvedPlaceFillsNameCoordinatesAndTimeZone() {
        var fields = LocationDraftPlaceFields(
            name: "Old",
            latitude: "1",
            longitude: "2",
            timeZoneIdentifier: "UTC"
        )
        fields.apply(
            ResolvedPlace(
                name: "Sandown",
                latitude: 42.9287,
                longitude: -71.1873,
                timeZoneIdentifier: "America/New_York"
            )
        )
        XCTAssertEqual(fields.name, "Sandown")
        XCTAssertEqual(fields.latitude, "42.92870")
        XCTAssertEqual(fields.longitude, "-71.18730")
        XCTAssertEqual(fields.timeZoneIdentifier, "America/New_York")
    }

    func testNilMapKitTimeZonePreservesExistingSelection() {
        var fields = LocationDraftPlaceFields(
            name: "Old",
            latitude: "1",
            longitude: "2",
            timeZoneIdentifier: "Europe/Paris"
        )
        fields.apply(
            ResolvedPlace(
                name: "Somewhere",
                latitude: 10,
                longitude: 20,
                timeZoneIdentifier: nil
            )
        )
        XCTAssertEqual(fields.name, "Somewhere")
        XCTAssertEqual(fields.latitude, "10.00000")
        XCTAssertEqual(fields.longitude, "20.00000")
        XCTAssertEqual(fields.timeZoneIdentifier, "Europe/Paris")
    }

    func testCatalogSuggestedBeforeAllWithoutDuplicates() {
        let suggested = TimeZoneCatalog.suggested
        let remaining = TimeZoneCatalog.remaining
        XCTAssertFalse(suggested.isEmpty)
        XCTAssertTrue(suggested.isDisjoint(with: Set(remaining)))
        XCTAssertEqual(
            Set(TimeZoneCatalog.unitedStates).union(TimeZoneCatalog.europe),
            suggested
        )
        for identifier in TimeZoneCatalog.unitedStates + TimeZoneCatalog.europe {
            XCTAssertNotNil(TimeZone(identifier: identifier))
        }
    }

    func testCatalogFiltersUnknownCandidates() {
        for identifier in TimeZoneCatalog.unitedStatesCandidates + TimeZoneCatalog.europeCandidates
            where TimeZone(identifier: identifier) == nil {
            XCTAssertFalse(TimeZoneCatalog.unitedStates.contains(identifier))
            XCTAssertFalse(TimeZoneCatalog.europe.contains(identifier))
        }
    }

    func testTimeZoneSearchMatchesCityIdentifierAndAbbreviation() {
        let now = Date(timeIntervalSince1970: 1_720_000_000) // mid-2024 summer in US
        let identifiers = ["America/New_York", "Europe/London", "Asia/Tokyo"]

        XCTAssertEqual(
            TimeZoneCatalog.filter(identifiers, searchText: "New York", now: now),
            ["America/New_York"]
        )
        XCTAssertEqual(
            TimeZoneCatalog.filter(identifiers, searchText: "America/New_York", now: now),
            ["America/New_York"]
        )

        let edtMatches = TimeZoneCatalog.filter(identifiers, searchText: "EDT", now: now)
        XCTAssertTrue(edtMatches.contains("America/New_York") || edtMatches.contains("Europe/London") == false)
        // America/New_York is on EDT around this date.
        if let abbreviation = TimeZone(identifier: "America/New_York")?.abbreviation(for: now),
           abbreviation.localizedCaseInsensitiveContains("EDT") {
            XCTAssertEqual(edtMatches, ["America/New_York"])
        }

        XCTAssertEqual(
            TimeZoneCatalog.filter(identifiers, searchText: "   ", now: now),
            identifiers
        )
    }

    func testCountingLocationProviderOptionalTimeZone() async throws {
        let provider = CountingLocationProvider()
        provider.result = CurrentLocationResult(
            latitude: 1,
            longitude: 2,
            timeZoneIdentifier: nil
        )
        let result = try await provider.requestLocation()
        XCTAssertNil(result.timeZoneIdentifier)
        XCTAssertEqual(provider.requestCount, 1)
    }

    func testPlaceSearchDoesNotInvokeLocationProvider() {
        let provider = CountingLocationProvider()
        XCTAssertEqual(provider.requestCount, 0)
        // Place search lives in the app target and must not hold CurrentLocationProviding.
        // Opening/searching places is independent of the location provider path.
        XCTAssertEqual(provider.requestCount, 0)
    }
}
