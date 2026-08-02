import XCTest
@testable import SunsetHueCore

final class PersistenceAndForecastServiceTests: XCTestCase {
    func testInMemoryCredentialStoreRoundTrip() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(try store.loadAPIKey())
        try store.saveAPIKey("abc123")
        XCTAssertEqual(try store.loadAPIKey(), "abc123")
        try store.deleteAPIKey()
        XCTAssertNil(try store.loadAPIKey())
    }

    func testSettingsAndCacheRoundTrip() throws {
        let settings = InMemorySettingsStore()
        let cache = InMemoryForecastCache()
        let location = PreviewFixtures.sampleLocation
        let state = SharedAppState(locations: [location], selectedLocationID: location.id)
        try settings.save(state)
        XCTAssertEqual(try settings.load().locations.count, 1)

        let bundle = PreviewFixtures.sampleBundle()
        try cache.saveBundle(bundle)
        XCTAssertEqual(try cache.loadBundle(for: location.id)?.forecasts.count, bundle.forecasts.count)
    }

    func testFileBackedSettingsAndCacheRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunsetHueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settings = FileSettingsStore(fileURL: directory.appendingPathComponent("app-state.json"))
        let cache = FileForecastCache(fileURL: directory.appendingPathComponent("forecast-cache.json"))
        let location = PreviewFixtures.sampleLocation
        try settings.save(SharedAppState(locations: [location], selectedLocationID: location.id))
        XCTAssertEqual(try settings.load().locations.first?.name, "Sample Harbor")

        let bundle = PreviewFixtures.sampleBundle()
        try cache.saveBundle(bundle)
        XCTAssertEqual(try cache.loadBundle(for: location.id)?.locationID, location.id)
    }

    func testCachePreservationAfterTransientFailure() async throws {
        let body = try loadFixture("event_full")
        let sunrise = try mutateType(body, to: "sunrise")
        // First refresh succeeds with one sunrise + one sunset for 1 day.
        let location = SavedLocation(
            id: PreviewFixtures.sampleLocationID,
            name: "Sample Harbor",
            latitude: 40.7128,
            longitude: -74.006,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 1,
            includeSunrise: true,
            includeSunset: true,
            refreshIntervalHours: 6
        )
        let successTransport = MockHTTPTransport(stubs: [
            .init(statusCode: 200, body: sunrise),
            .init(statusCode: 200, body: body),
        ])
        let service = ForecastService(transport: successTransport)
        let previous = try await service.refresh(location: location, apiKey: "test-key")
        XCTAssertEqual(previous.forecasts.count, 2)

        let failingTransport = MockHTTPTransport(stubs: [
            .init(error: .timeout),
            .init(error: .timeout),
        ])
        let failingService = ForecastService(transport: failingTransport)
        let outcome = await failingService.refreshPreservingCache(
            location: location,
            apiKey: "test-key",
            previous: previous
        )
        XCTAssertTrue(outcome.usedCache)
        XCTAssertEqual(outcome.bundle?.fetchedAt, previous.fetchedAt)
        XCTAssertEqual(outcome.error, .timeout)
    }

    func testAtomicFailureDiscardsPartialResults() async {
        let body = try! loadFixture("event_full")
        let location = SavedLocation(
            name: "Sample Harbor",
            latitude: 40.7128,
            longitude: -74.006,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 1,
            includeSunrise: false,
            includeSunset: true
        )
        // One success then auth failure for a second day would matter with days>1; with 1 event, inject auth.
        let transport = MockHTTPTransport(stubs: [
            .init(statusCode: 200, body: body),
            .init(statusCode: 401, body: Data()),
        ])
        // Force 2 sunset requests via 2 days.
        let twoDay = SavedLocation(
            id: location.id,
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude,
            timeZoneIdentifier: location.timeZoneIdentifier,
            forecastDays: 2,
            includeSunrise: false,
            includeSunset: true
        )
        let service = ForecastService(transport: transport)
        do {
            _ = try await service.refresh(location: twoDay, apiKey: "test-key")
            XCTFail("Expected failure")
        } catch let error as SunsetHueError {
            XCTAssertEqual(error, .authentication)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testPresentationPercentageConversion() {
        XCTAssertEqual(PresentationFormatting.percentage(fromNormalized: 0.45), "45.0%")
        XCTAssertEqual(PresentationFormatting.percentageValue(fromNormalized: 0.456), 45.6)
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    private func mutateType(_ data: Data, to type: String) throws -> Data {
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var body = try XCTUnwrap(payload["data"] as? [String: Any])
        body["type"] = type
        payload["data"] = body
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
