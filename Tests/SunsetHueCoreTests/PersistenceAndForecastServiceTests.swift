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

    func testSettingsAndCacheRoundTrip() async throws {
        let settings = InMemorySettingsStore()
        let cache = InMemoryForecastCache()
        let location = PreviewFixtures.sampleLocation
        let state = SharedAppState(locations: [location], selectedLocationID: location.id)
        try await settings.save(state)
        let loaded = try await settings.load()
        XCTAssertEqual(loaded.value.locations.count, 1)

        let bundle = PreviewFixtures.sampleBundle()
        try await cache.saveSnapshot(.fromSuccessful(bundle: bundle))
        let loadedBundle = try await cache.loadBundle(for: location.id)
        XCTAssertEqual(loadedBundle?.forecasts.count, bundle.forecasts.count)
    }

    func testFileBackedSettingsAndCacheRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunsetHueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settings = FileSettingsStore(fileURL: directory.appendingPathComponent("app-state.json"))
        let cache = FileForecastCache(rootDirectory: directory)
        let location = PreviewFixtures.sampleLocation
        try await settings.save(SharedAppState(locations: [location], selectedLocationID: location.id))
        let loadedName = try await settings.load().value.locations.first?.name
        XCTAssertEqual(loadedName, "Sample Harbor")

        let bundle = PreviewFixtures.sampleBundle()
        try await cache.saveSnapshot(.fromSuccessful(bundle: bundle))
        let loadedID = try await cache.loadBundle(for: location.id)?.locationID
        XCTAssertEqual(loadedID, location.id)
    }

    func testLegacyMonolithicCacheMigration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunsetHueMigrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let locationID = PreviewFixtures.sampleLocationID
        let bundle = PreviewFixtures.sampleBundle()
        let legacy = CachedForecastStore(bundles: [locationID: bundle])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyURL = directory.appendingPathComponent("forecast-cache.json")
        try encoder.encode(legacy).write(to: legacyURL)

        let cache = FileForecastCache(rootDirectory: directory)
        let migrated = try await cache.loadBundle(for: locationID)
        XCTAssertEqual(migrated?.locationID, locationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testOlderFetchedAtRejected() async throws {
        let cache = InMemoryForecastCache()
        let id = PreviewFixtures.sampleLocationID
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = CachedLocationSnapshot(
            locationID: id,
            fetchedAt: base.addingTimeInterval(3600),
            lastAttemptAt: base.addingTimeInterval(3600),
            forecasts: [],
            status: .current
        )
        let older = CachedLocationSnapshot(
            locationID: id,
            fetchedAt: base,
            lastAttemptAt: base,
            forecasts: [PreviewFixtures.excellentSunset()],
            status: .current
        )
        try await cache.saveSnapshot(newer)
        try await cache.saveSnapshot(older)
        let loaded = try await cache.loadSnapshot(for: id)
        XCTAssertEqual(loaded?.forecasts.count, 0)
        XCTAssertEqual(loaded?.fetchedAt, newer.fetchedAt)
    }

    func testCorruptSettingsRenamed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunsetHueCorrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settingsURL = directory.appendingPathComponent("app-state.json")
        try Data("{not-json".utf8).write(to: settingsURL)
        let settings = FileSettingsStore(fileURL: settingsURL)
        let result = try await settings.load()
        XCTAssertTrue(result.value.locations.isEmpty)
        XCTAssertEqual(result.recovery?.reason, .corrupt)
        XCTAssertNotNil(result.recovery?.quarantineFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    func testDeleteLocationPrunesCacheFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunsetHueDelete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = FileForecastCache(rootDirectory: directory)
        let bundle = PreviewFixtures.sampleBundle()
        try await cache.saveSnapshot(.fromSuccessful(bundle: bundle))
        try await cache.deleteLocation(bundle.locationID)
        let afterDelete = try await cache.loadBundle(for: bundle.locationID)
        XCTAssertNil(afterDelete)
    }

    func testCachePreservationAfterTransientFailure() async throws {
        let body = try loadFixture("event_full")
        let sunrise = try mutateType(body, to: "sunrise")
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
        let transport = MockHTTPTransport(stubs: [
            .init(statusCode: 200, body: body),
            .init(statusCode: 401, body: Data()),
        ])
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

    func testKeychainStatusMapper() {
        XCTAssertEqual(KeychainStatusMapper.error(for: errSecInteractionNotAllowed), .keychainUnavailable)
        XCTAssertEqual(KeychainStatusMapper.error(for: errSecItemNotFound), .missingCredentials)
        XCTAssertEqual(KeychainStatusMapper.error(for: errSecMissingEntitlement), .keychainEntitlementMisconfigured)
        XCTAssertEqual(KeychainStatusMapper.error(for: errSecInvalidOwnerEdit), .keychainEntitlementMisconfigured)
    }

    func testPresentationPercentageConversion() {
        XCTAssertEqual(PresentationFormatting.percentage(fromNormalized: 0.45), "45.0%")
        XCTAssertEqual(PresentationFormatting.percentageValue(fromNormalized: 0.456), 45.6)
    }

    func testPresentationTimeStringRespectsTwelveHourLocale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 20, minute: 6))!
        let formatted = PresentationFormatting.timeString(
            date,
            timeZone: TimeZone(identifier: "America/New_York")!,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertNotNil(formatted)
        XCTAssertTrue(formatted?.contains("4:06") == true, "expected 4:06 in \(formatted ?? "nil")")
        XCTAssertTrue(formatted?.localizedCaseInsensitiveContains("PM") == true, "expected PM in \(formatted ?? "nil")")
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
