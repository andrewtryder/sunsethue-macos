import XCTest
@testable import SunsetHueCore

/// Transport whose responses are held until `release()` so tests can interleave
/// location edits/deletions with an in-flight refresh deterministically.
final class GatedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private var count = 0
    private let body: Data

    init(body: Data) { self.body = body }

    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func perform(_ request: URLRequest) async throws -> HTTPResponse {
        lock.lock(); count += 1; lock.unlock()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
        return HTTPResponse(statusCode: 200, headers: [:], body: body)
    }

    func release() {
        lock.lock()
        isOpen = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    func waitUntilRequested(minimum: Int = 1) async throws {
        for _ in 0..<400 where requestCount < minimum {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertGreaterThanOrEqual(requestCount, minimum, "Timed out waiting for request")
    }
}

final class LocationLifecycleTests: XCTestCase {
    private func makeLocation(
        id: UUID = UUID(),
        name: String = "Home",
        latitude: Double = 40.7128,
        longitude: Double = -74.006,
        timeZone: String = "America/New_York",
        forecastDays: Int = 2,
        sunrise: Bool = true,
        sunset: Bool = true
    ) -> SavedLocation {
        SavedLocation(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZone,
            forecastDays: forecastDays,
            includeSunrise: sunrise,
            includeSunset: sunset,
            refreshIntervalHours: 6
        )
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    private func makeCoordinator(
        location: SavedLocation,
        transport: any HTTPTransport,
        cache: InMemoryForecastCache = InMemoryForecastCache()
    ) -> (ForecastRefreshCoordinator, InMemorySettingsStore, InMemoryForecastCache) {
        let settings = InMemorySettingsStore(state: SharedAppState(locations: [location]))
        let coordinator = ForecastRefreshCoordinator(
            settingsStore: settings,
            forecastCache: cache,
            credentialStore: InMemoryCredentialStore(apiKey: "test-key"),
            forecastService: ForecastService(transport: transport)
        )
        return (coordinator, settings, cache)
    }

    private func oldSnapshot(for location: SavedLocation, now: Date = Date()) -> CachedLocationSnapshot {
        CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: now.addingTimeInterval(-3600),
            lastAttemptAt: now.addingTimeInterval(-3600),
            forecasts: [
                EventForecast(
                    responseTime: now,
                    location: location.coordinates,
                    gridLocation: location.coordinates,
                    eventType: .sunset,
                    modelData: true,
                    quality: 0.9,
                    qualityText: "Great",
                    cloudCover: 0.2,
                    eventTime: now.addingTimeInterval(7200),
                    direction: 270,
                    blueHour: nil,
                    goldenHour: nil,
                    forecastDate: now
                )
            ],
            status: .current
        )
    }

    // MARK: - Identity comparison

    func testDisplayOnlyEditsDoNotInvalidateCache() {
        let original = makeLocation()
        var renamed = original
        renamed.name = "Renamed"
        renamed.forecastDays = 3
        renamed.refreshIntervalHours = 12
        XCTAssertFalse(renamed.invalidatesCachedForecasts(comparedTo: original))

        var jitter = original
        jitter.latitude += 0.000_000_01
        XCTAssertFalse(jitter.invalidatesCachedForecasts(comparedTo: original))
    }

    func testMeaningfulEditsInvalidateCache() {
        let original = makeLocation()
        var moved = original
        moved.latitude = 51.5
        XCTAssertTrue(moved.invalidatesCachedForecasts(comparedTo: original))

        var otherZone = original
        otherZone.timeZoneIdentifier = "America/Los_Angeles"
        XCTAssertTrue(otherZone.invalidatesCachedForecasts(comparedTo: original))

        var sunsetOnly = original
        sunsetOnly.includeSunrise = false
        XCTAssertTrue(sunsetOnly.invalidatesCachedForecasts(comparedTo: original))
    }

    // MARK: - Cache preservation / invalidation

    func testRenameKeepsCacheAndTriggersNoNetworkRequest() async throws {
        let location = makeLocation()
        var snapshot = oldSnapshot(for: location)
        snapshot.fetchedAt = Date()
        snapshot.lastAttemptAt = Date()
        // Two days of coverage so a non-forced refresh has nothing to do.
        let transport = MockHTTPTransport()
        let cache = InMemoryForecastCache(snapshots: [location.id: snapshot])
        let (coordinator, settings, _) = makeCoordinator(location: location, transport: transport, cache: cache)

        var renamed = location
        renamed.name = "Renamed"
        try await settings.save(SharedAppState(locations: [renamed]))
        XCTAssertFalse(renamed.invalidatesCachedForecasts(comparedTo: location))
        // AppModel calls refreshLocation(force: false) for non-meaningful edits.
        _ = await coordinator.refreshLocation(id: location.id, force: false)

        let kept = try await cache.loadSnapshot(for: location.id)
        XCTAssertEqual(kept?.forecasts.count, 1, "Cache must survive a display-name change")
        XCTAssertEqual(kept?.forecasts.first?.location, location.coordinates)
    }

    func testFailedRefreshAfterCoordinateChangeDoesNotShowPreviousLocationForecast() async throws {
        let location = makeLocation()
        let cache = InMemoryForecastCache(snapshots: [location.id: oldSnapshot(for: location)])
        let failing = MockHTTPTransport() // no stubs -> networkUnavailable
        let (coordinator, settings, _) = makeCoordinator(location: location, transport: failing, cache: cache)

        var moved = location
        moved.latitude = 34.05
        moved.longitude = -118.24
        moved.timeZoneIdentifier = "America/Los_Angeles"
        try await settings.save(SharedAppState(locations: [moved]))
        await coordinator.locationForecastIdentityChanged(id: moved.id)

        let afterFailure = await coordinator.refreshLocation(id: moved.id, force: true)
        XCTAssertNotNil(afterFailure)
        XCTAssertTrue(afterFailure?.forecasts.isEmpty ?? false, "Old location's forecasts must not be shown")
        XCTAssertEqual(afterFailure?.status, .temporarilyUnavailable)

        let stored = try await cache.loadSnapshot(for: moved.id)
        XCTAssertTrue(stored?.forecasts.isEmpty ?? false)
    }

    func testEnabledEventChangeLeavesNoStaleForecasts() async throws {
        let location = makeLocation()
        let cache = InMemoryForecastCache(snapshots: [location.id: oldSnapshot(for: location)])
        let (coordinator, settings, _) = makeCoordinator(location: location, transport: MockHTTPTransport(), cache: cache)

        var sunriseOnly = location
        sunriseOnly.includeSunset = false
        try await settings.save(SharedAppState(locations: [sunriseOnly]))
        await coordinator.locationForecastIdentityChanged(id: location.id)

        let stored = try await cache.loadSnapshot(for: location.id)
        XCTAssertNil(stored)
    }

    // MARK: - Races

    func testRemovalDuringInFlightRefreshDoesNotRecreateCache() async throws {
        let location = makeLocation()
        let transport = GatedTransport(body: try loadFixture("event_full"))
        let (coordinator, settings, cache) = makeCoordinator(location: location, transport: transport)

        let refresh = Task { await coordinator.refreshLocation(id: location.id, force: true) }
        try await transport.waitUntilRequested()

        try await settings.save(SharedAppState(locations: []))
        await coordinator.locationRemoved(id: location.id)
        transport.release()

        let result = await refresh.value
        XCTAssertNil(result)
        let stored = try await cache.loadSnapshot(for: location.id)
        XCTAssertNil(stored, "Stale completion must not recreate a deleted location's cache")

        // Later refresh attempts for the removed id are no-ops.
        let again = await coordinator.refreshLocation(id: location.id, force: true)
        XCTAssertNil(again)
        let storedAfter = try await cache.loadSnapshot(for: location.id)
        XCTAssertNil(storedAfter)
    }

    func testEditDuringInFlightRefreshDiscardsOldCoordinateResult() async throws {
        let location = makeLocation()
        let transport = GatedTransport(body: try loadFixture("event_full"))
        let (coordinator, settings, cache) = makeCoordinator(location: location, transport: transport)

        let refresh = Task { await coordinator.refreshLocation(id: location.id, force: true) }
        try await transport.waitUntilRequested()

        var moved = location
        moved.latitude = 34.05
        try await settings.save(SharedAppState(locations: [moved]))
        await coordinator.locationForecastIdentityChanged(id: moved.id)
        transport.release()

        _ = await refresh.value
        let stored = try await cache.loadSnapshot(for: location.id)
        XCTAssertNil(stored, "Result fetched for the previous coordinates must be discarded")
    }

    func testOverlappingRefreshesAreSingleFlight() async throws {
        let location = makeLocation(forecastDays: 2, sunrise: false, sunset: true)
        let transport = GatedTransport(body: try loadFixture("event_full"))
        let (coordinator, _, cache) = makeCoordinator(location: location, transport: transport)

        let first = Task { await coordinator.refreshLocation(id: location.id, force: false) }
        try await transport.waitUntilRequested()
        let second = Task { await coordinator.refreshLocation(id: location.id, force: false) }
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.release()

        let a = await first.value
        let b = await second.value
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.fetchedAt, b?.fetchedAt)
        XCTAssertEqual(transport.requestCount, 2, "One day-set (2 days x 1 event) fetched exactly once")
        let stored = try await cache.loadSnapshot(for: location.id)
        XCTAssertEqual(stored?.forecasts.count, 2)
    }

    // MARK: - Manual refresh consistency

    func testManualRefreshAllFetchesEvenWhenCacheIsFresh() async throws {
        let location = makeLocation(forecastDays: 2, sunrise: false, sunset: true)
        let body = try loadFixture("event_full")
        let transport = MockHTTPTransport(stubs: [.init(statusCode: 200, body: body), .init(statusCode: 200, body: body)])
        let (coordinator, _, cache) = makeCoordinator(location: location, transport: transport)

        await coordinator.refreshAllLocations()
        let first = try await cache.loadSnapshot(for: location.id)
        XCTAssertEqual(first?.status, .current)
        XCTAssertEqual(transport.requests.count, 2)

        // Fresh cache: the scheduled path skips, the manual path fetches again.
        await coordinator.refreshAllStaleLocations(trigger: .scheduled)
        XCTAssertEqual(transport.requests.count, 2)
        transport.enqueue(.init(statusCode: 200, body: body))
        transport.enqueue(.init(statusCode: 200, body: body))
        await coordinator.refreshAllLocations()
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testManualRefreshAllRespectsActiveRateLimitDeadline() async throws {
        let location = makeLocation()
        var limited = oldSnapshot(for: location)
        limited.status = .rateLimited(retryAfter: Date().addingTimeInterval(1800))
        let transport = MockHTTPTransport()
        let cache = InMemoryForecastCache(snapshots: [location.id: limited])
        let (coordinator, _, _) = makeCoordinator(location: location, transport: transport, cache: cache)

        await coordinator.refreshAllLocations()
        XCTAssertTrue(transport.requests.isEmpty, "Manual refresh must not bypass Retry-After")
        let stored = try await cache.loadSnapshot(for: location.id)
        XCTAssertEqual(stored?.status, limited.status)
    }
}
