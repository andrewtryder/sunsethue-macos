@testable import SunsetHueCore
import XCTest

final class ModelRunInfoTests: XCTestCase {
    private let oldRun = "2026-11-20-06z"
    private let newRun = "2026-11-20-12z"

    func testParsesTopLevelEventMetadataAndPreservesThroughDateMapping() throws {
        let body = try eventResponse(runID: newRun)
        let event = try ResponseParser.parseEventForecast(data: body, expectedEventType: .sunset)
        XCTAssertEqual(event.modelRunIdentifier, newRun)
        XCTAssertEqual(event.nextExpectedUpdate, try XCTUnwrap(isoDate("2026-11-20T17:00:00Z")))
        XCTAssertEqual(event.withForecastDate(Date()).modelRunIdentifier, newRun)
    }

    func testParsesNestedRunInfo() throws {
        let body = Data("""
        {
          "data": {
            "current_run": {"id": "2026-11-20-12z"},
            "next_run": {"expected_at": "2026-11-20T23:00:00Z"}
          }
        }
        """.utf8)
        let parsed = try ModelRunInfoParser.parse(body)
        XCTAssertEqual(parsed.identifier, newRun)
        XCTAssertEqual(parsed.nextExpectedUpdate, isoDate("2026-11-20T23:00:00Z"))
    }

    func testUnknownMetadataFailsClosed() {
        let body = Data(#"{"data":{"message":"unknown contract"}}"#.utf8)
        XCTAssertThrowsError(try ModelRunInfoParser.parse(body))
    }

    func testRunInfoRequestUsesApiKeyHeader() async throws {
        let transport = MockHTTPTransport(stubs: [.init(body: runResponse(runID: newRun))])
        let service = ModelRunInfoService(transport: transport)
        let result = try await service.fetch(apiKey: "test-key")
        XCTAssertEqual(result.identifier, newRun)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/run-info")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertFalse(request.url?.absoluteString.contains("test-key") ?? true)
    }

    func testUnchangedRunSkipsEventRequests() async throws {
        let location = makeLocation()
        let eventTransport = MockHTTPTransport()
        let runTransport = MockHTTPTransport(stubs: [.init(body: runResponse(runID: oldRun))])
        let cache = InMemoryForecastCache(snapshots: [location.id: cachedSnapshot(for: location, runID: oldRun)])
        let coordinator = makeCoordinator(
            locations: [location],
            cache: cache,
            eventTransport: eventTransport,
            runTransport: runTransport
        )

        let updated = await coordinator.refreshLocation(id: location.id, force: false)
        XCTAssertEqual(eventTransport.requests.count, 0)
        XCTAssertEqual(runTransport.requests.count, 1)
        XCTAssertEqual(updated?.modelRunIdentifier, oldRun)
        XCTAssertGreaterThan(try XCTUnwrap(updated?.nextAttemptAt), Date())
        XCTAssertEqual(updated?.fetchedAt, try XCTUnwrap(await cache.loadSnapshot(for: location.id)?.fetchedAt))
    }

    func testOneRunInfoCheckSharedAcrossLocations() async throws {
        let first = makeLocation()
        let second = SavedLocation(
            name: "Second location",
            latitude: 42,
            longitude: -72,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 1,
            includeSunrise: false,
            includeSunset: true
        )
        let cache = InMemoryForecastCache(snapshots: [
            first.id: cachedSnapshot(for: first, runID: oldRun),
            second.id: cachedSnapshot(for: second, runID: oldRun),
        ])
        let eventTransport = MockHTTPTransport()
        let runTransport = MockHTTPTransport(stubs: [.init(body: runResponse(runID: oldRun))])
        let coordinator = makeCoordinator(
            locations: [first, second],
            cache: cache,
            eventTransport: eventTransport,
            runTransport: runTransport
        )

        await coordinator.refreshAllStaleLocations()
        XCTAssertEqual(eventTransport.requests.count, 0)
        XCTAssertEqual(runTransport.requests.count, 1)
    }

    func testNewRunFetchesForecastEvents() async throws {
        let location = makeLocation()
        let eventBody = try eventResponse(runID: newRun)
        let eventTransport = MockHTTPTransport(stubs: [
            .init(body: eventBody),
            .init(body: eventBody),
        ])
        let runTransport = MockHTTPTransport(stubs: [.init(body: runResponse(runID: newRun))])
        let cache = InMemoryForecastCache(snapshots: [location.id: cachedSnapshot(for: location, runID: oldRun)])
        let coordinator = makeCoordinator(
            locations: [location],
            cache: cache,
            eventTransport: eventTransport,
            runTransport: runTransport
        )

        let result = await coordinator.refreshLocation(id: location.id, force: false)
        XCTAssertEqual(runTransport.requests.count, 1)
        XCTAssertEqual(eventTransport.requests.count, 2)
        XCTAssertEqual(result?.modelRunIdentifier, newRun)
    }

    func testLegacySnapshotBypassesRunInfo() async throws {
        let location = makeLocation()
        let eventBody = try eventResponse(runID: nil)
        let eventTransport = MockHTTPTransport(stubs: [
            .init(body: eventBody),
            .init(body: eventBody),
        ])
        let runTransport = MockHTTPTransport()
        let cache = InMemoryForecastCache(snapshots: [location.id: cachedSnapshot(for: location, runID: nil)])
        let coordinator = makeCoordinator(
            locations: [location],
            cache: cache,
            eventTransport: eventTransport,
            runTransport: runTransport
        )

        _ = await coordinator.refreshLocation(id: location.id, force: false)
        XCTAssertEqual(eventTransport.requests.count, 2)
        XCTAssertTrue(runTransport.requests.isEmpty)
    }

    func testMissingCoverageRefreshesEvenWhenRunIsUnchanged() async throws {
        let location = makeLocation()
        var incomplete = cachedSnapshot(for: location, runID: oldRun)
        incomplete.forecasts = [PreviewFixtures.excellentSunset(on: Date())]
        let eventBody = try eventResponse(runID: oldRun)
        let eventTransport = MockHTTPTransport(stubs: [
            .init(body: eventBody),
            .init(body: eventBody),
        ])
        let runTransport = MockHTTPTransport()
        let cache = InMemoryForecastCache(snapshots: [location.id: incomplete])
        let coordinator = makeCoordinator(
            locations: [location],
            cache: cache,
            eventTransport: eventTransport,
            runTransport: runTransport
        )

        _ = await coordinator.refreshLocation(id: location.id, force: false)
        XCTAssertEqual(eventTransport.requests.count, 2)
        XCTAssertTrue(runTransport.requests.isEmpty)
    }

    func testSnapshotRunMetadataSurvivesCacheEncoding() throws {
        let location = makeLocation()
        let snapshot = cachedSnapshot(for: location, runID: oldRun)
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CachedLocationSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.modelRunIdentifier, oldRun)
        XCTAssertEqual(decoded, snapshot)
    }

    private func makeLocation() -> SavedLocation {
        SavedLocation(
            id: PreviewFixtures.sampleLocationID,
            name: "Test location",
            latitude: 40.7128,
            longitude: -74.006,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 1,
            includeSunrise: false,
            includeSunset: true,
            refreshIntervalHours: 6
        )
    }

    private func cachedSnapshot(for location: SavedLocation, runID: String?) -> CachedLocationSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PreviewFixtures.sampleTimeZone
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        let fetched = Date().addingTimeInterval(-7 * 3600)
        return CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: fetched,
            lastAttemptAt: fetched,
            forecasts: [
                PreviewFixtures.excellentSunset(on: today),
                PreviewFixtures.excellentSunset(on: tomorrow).withForecastDate(tomorrow),
            ],
            status: .current,
            modelRunIdentifier: runID
        )
    }

    private func makeCoordinator(
        locations: [SavedLocation],
        cache: InMemoryForecastCache,
        eventTransport: MockHTTPTransport,
        runTransport: MockHTTPTransport
    ) -> ForecastRefreshCoordinator {
        ForecastRefreshCoordinator(
            settingsStore: InMemorySettingsStore(state: SharedAppState(locations: locations)),
            forecastCache: cache,
            credentialStore: InMemoryCredentialStore(apiKey: "test-key"),
            forecastService: ForecastService(transport: eventTransport),
            runInfoMonitor: ModelRunInfoMonitor(service: ModelRunInfoService(transport: runTransport))
        )
    }

    private func runResponse(runID: String) -> Data {
        Data("""
        {"run_id":"\(runID)","next_expected_update":"2026-11-20T23:00:00Z"}
        """.utf8)
    }

    private func eventResponse(runID: String?) throws -> Data {
        var payload: [String: Any] = [
            "time": "2026-11-20T12:00:00Z",
            "location": ["latitude": 40.7128, "longitude": -74.006],
            "grid_location": ["latitude": 41, "longitude": -74],
            "data": ["type": "sunset", "model_data": true],
        ]
        if let runID {
            payload["run_id"] = runID
            payload["next_expected_update"] = "2026-11-20T17:00:00Z"
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)
    }
}
