import XCTest
@testable import SunsetHueCore

final class DiagnosticsAndLocationProviderTests: XCTestCase {
    func testDiagnosticsRedactsSecretsAndExactCoordinates() throws {
        let location = PreviewFixtures.sampleLocation
        let secret = "super-secret-api-key-value"
        let snapshot = CachedLocationSnapshot.fromSuccessful(bundle: PreviewFixtures.sampleBundle())
        let data = try DiagnosticsExporter().makeReport(
            state: SharedAppState(locations: [location], selectedLocationID: location.id),
            snapshots: [location.id: snapshot],
            apiKeyConfigured: true,
            apiKeyValueForRedactionTests: secret,
            options: DiagnosticsExportOptions(includeApproximateCoordinates: false),
            appVersion: "1.2.0",
            build: "14"
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("\(location.latitude)"))
        XCTAssertFalse(text.contains("\(location.longitude)"))
        XCTAssertFalse(text.contains(location.name))
        XCTAssertFalse(text.lowercased().contains("x-api-key"))
        XCTAssertTrue(text.contains("\"configured\" : true") || text.contains("\"configured\": true"))
        XCTAssertTrue(text.contains("redacted"))
    }

    func testApproximateCoordinatesRoundedToOneDecimal() throws {
        let location = PreviewFixtures.sampleLocation
        let data = try DiagnosticsExporter().makeReport(
            state: SharedAppState(locations: [location]),
            snapshots: [:],
            apiKeyConfigured: false,
            options: DiagnosticsExportOptions(includeApproximateCoordinates: true)
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("40.7") || text.contains(String(format: "%.1f", location.latitude)))
        XCTAssertFalse(text.contains(String(format: "%.5f", location.latitude)))
    }

    func testCountingLocationProviderOnlyIncrementsOnRequest() async throws {
        let provider = CountingLocationProvider()
        XCTAssertEqual(provider.requestCount, 0)
        // Opening editor / typing / testing API must not call the provider.
        XCTAssertEqual(provider.requestCount, 0)
        _ = try await provider.requestLocation()
        XCTAssertEqual(provider.requestCount, 1)
    }

    func testCoordinatorWritesAuthenticationSnapshotWithoutNetworkKey() async throws {
        let location = PreviewFixtures.sampleLocation
        let settings = InMemorySettingsStore(state: SharedAppState(locations: [location], selectedLocationID: location.id))
        let cache = InMemoryForecastCache()
        let credentials = InMemoryCredentialStore()
        let coordinator = ForecastRefreshCoordinator(
            settingsStore: settings,
            forecastCache: cache,
            credentialStore: credentials,
            forecastService: ForecastService(transport: MockHTTPTransport())
        )
        let snapshot = await coordinator.refreshLocation(id: location.id, force: true)
        XCTAssertEqual(snapshot?.status, .authenticationRequired)
        let loaded = try await cache.loadSnapshot(for: location.id)
        XCTAssertEqual(loaded?.status, .authenticationRequired)
    }

    func testMarkAllSnapshotsAuthenticationRequiredPreservesForecasts() async throws {
        let location = PreviewFixtures.sampleLocation
        let bundle = PreviewFixtures.sampleBundle()
        let settings = InMemorySettingsStore(state: SharedAppState(locations: [location], selectedLocationID: location.id))
        let cache = InMemoryForecastCache(snapshots: [
            location.id: .fromSuccessful(bundle: bundle)
        ])
        let coordinator = ForecastRefreshCoordinator(
            settingsStore: settings,
            forecastCache: cache,
            credentialStore: InMemoryCredentialStore(apiKey: "temporary"),
            forecastService: ForecastService(transport: MockHTTPTransport())
        )
        await coordinator.markAllSnapshotsAuthenticationRequired()
        let loaded = try await cache.loadSnapshot(for: location.id)
        XCTAssertEqual(loaded?.status, .authenticationRequired)
        XCTAssertEqual(loaded?.forecasts.count, bundle.forecasts.count)
        XCTAssertNil(loaded?.nextAttemptAt)
    }
}
