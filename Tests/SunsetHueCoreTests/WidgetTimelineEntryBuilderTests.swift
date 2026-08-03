import XCTest
@testable import SunsetHueCore

final class WidgetTimelineEntryBuilderTests: XCTestCase {
    func testMissingCacheNeverUsesPreviewFixtures() {
        let location = PreviewFixtures.sampleLocation
        let entry = WidgetTimelineEntryBuilder.makeEntry(location: location, snapshot: nil)

        XCTAssertEqual(entry.kind, .unavailable)
        XCTAssertNil(entry.bundle)
        XCTAssertEqual(entry.statusMessage, WidgetTimelineEntryBuilder.missingCacheMessage)
        XCTAssertNotEqual(entry.bundle?.locationID, PreviewFixtures.sampleLocationID)
        XCTAssertFalse(entry.bundle?.forecasts.isEmpty == false)
    }

    func testNilBundleSnapshotDoesNotInjectPreviewFixtures() {
        let location = PreviewFixtures.sampleLocation
        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: Date(),
            lastAttemptAt: Date(),
            forecasts: [],
            status: .temporarilyUnavailable
        )
        let entry = WidgetTimelineEntryBuilder.makeEntry(location: location, snapshot: snapshot)
        XCTAssertEqual(entry.kind, .unavailable)
        XCTAssertNil(entry.bundle)
    }

    func testAuthenticationKeepsCachedForecastsWithoutFixtures() {
        let location = PreviewFixtures.sampleLocation
        let sample = PreviewFixtures.sampleBundle()
        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: sample.fetchedAt,
            lastAttemptAt: Date(),
            forecasts: sample.forecasts,
            status: .authenticationRequired
        )
        let entry = WidgetTimelineEntryBuilder.makeEntry(location: location, snapshot: snapshot)
        XCTAssertEqual(entry.kind, .authentication)
        XCTAssertEqual(entry.bundle?.forecasts.count, sample.forecasts.count)
    }
}
