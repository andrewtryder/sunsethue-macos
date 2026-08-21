import XCTest
@testable import SunsetHueCore

final class OperationalForecastCoverageTests: XCTestCase {
    private let timeZoneNY = TimeZone(identifier: "America/New_York")!
    private let timeZoneTokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func makeLocation(
        id: UUID = UUID(),
        name: String = "Test City",
        forecastDays: Int = 1,
        timeZone: TimeZone = TimeZone(identifier: "America/New_York")!,
        sunrise: Bool = true,
        sunset: Bool = true
    ) -> SavedLocation {
        SavedLocation(
            id: id,
            name: name,
            latitude: 40.7128,
            longitude: -74.006,
            timeZoneIdentifier: timeZone.identifier,
            forecastDays: forecastDays,
            includeSunrise: sunrise,
            includeSunset: sunset,
            refreshIntervalHours: 6
        )
    }

    private func makeForecast(
        eventType: EventType,
        date: Date,
        eventTime: Date,
        quality: Double = 0.85
    ) -> EventForecast {
        EventForecast(
            responseTime: date,
            location: Coordinates(latitude: 40.7128, longitude: -74.006),
            gridLocation: Coordinates(latitude: 40.7128, longitude: -74.006),
            eventType: eventType,
            modelData: true,
            quality: quality,
            qualityText: "Good",
            cloudCover: 0.2,
            eventTime: eventTime,
            direction: 270.0,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: date
        )
    }

    // A. ForecastService with forecastDays == 1 fetches TWO local calendar days (today & tomorrow).
    func testForecastServiceWithOneForecastDayFetchesTwoLocalCalendarDays() async throws {
        let location = makeLocation(forecastDays: 1, sunrise: false, sunset: true)
        let body = try loadFixture("event_full")
        let transport = MockHTTPTransport(stubs: [
            .init(statusCode: 200, body: body),
            .init(statusCode: 200, body: body),
        ])
        let service = ForecastService(transport: transport)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneNY
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18, minute: 0))!

        let bundle = try await service.refresh(location: location, apiKey: "test-key", now: now)

        XCTAssertEqual(bundle.forecasts.count, 2)
        XCTAssertEqual(transport.requests.count, 2)

        let requestedDates = transport.requests.compactMap { req -> String? in
            guard let url = req.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            return components.queryItems?.first(where: { $0.name == "date" })?.value
        }.sorted()
        XCTAssertEqual(requestedDates, ["2026-08-20", "2026-08-21"])
    }

    // B. ForecastService with forecastDays == 2 remains two days.
    func testForecastServiceWithTwoForecastDaysFetchesTwoDays() async throws {
        let location = makeLocation(forecastDays: 2, sunrise: false, sunset: true)
        let body = try loadFixture("event_full")
        let transport = MockHTTPTransport(stubs: [
            .init(statusCode: 200, body: body),
            .init(statusCode: 200, body: body),
        ])
        let service = ForecastService(transport: transport)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneNY
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18, minute: 0))!

        let bundle = try await service.refresh(location: location, apiKey: "test-key", now: now)

        XCTAssertEqual(bundle.forecasts.count, 2)
        XCTAssertEqual(transport.requests.count, 2)
    }

    // C. ForecastService with forecastDays == 3 remains three days.
    func testForecastServiceWithThreeForecastDaysFetchesThreeDays() async throws {
        let location = makeLocation(forecastDays: 3, sunrise: false, sunset: true)
        let body = try loadFixture("event_full")
        let transport = MockHTTPTransport(stubs: [
            .init(statusCode: 200, body: body),
            .init(statusCode: 200, body: body),
            .init(statusCode: 200, body: body),
        ])
        let service = ForecastService(transport: transport)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneNY
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18, minute: 0))!

        let bundle = try await service.refresh(location: location, apiKey: "test-key", now: now)

        XCTAssertEqual(bundle.forecasts.count, 3)
        XCTAssertEqual(transport.requests.count, 3)
    }

    // D. Pre-sunset one-day legacy cache is considered operationally insufficient because tomorrow coverage is absent.
    func testPreSunsetOneDayCacheIsOperationallyInsufficient() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneNY
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 0, minute: 0))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18, minute: 0))!
        let sunsetTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 19, minute: 50))!

        let location = makeLocation(forecastDays: 1, sunrise: false, sunset: true)
        let forecastToday = makeForecast(eventType: .sunset, date: today, eventTime: sunsetTime)

        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: now.addingTimeInterval(-300),
            lastAttemptAt: now.addingTimeInterval(-300),
            forecasts: [forecastToday],
            status: .current
        )

        XCTAssertFalse(snapshot.hasOperationalCoverage(for: location, now: now))
    }

    // E. Two-day cache before sunset is operationally sufficient.
    func testTwoDayCacheBeforeSunsetIsOperationallySufficient() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneNY
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 0, minute: 0))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 0, minute: 0))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18, minute: 0))!
        let sunsetToday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 19, minute: 50))!
        let sunsetTomorrow = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 19, minute: 48))!

        let location = makeLocation(forecastDays: 1, sunrise: false, sunset: true)
        let fToday = makeForecast(eventType: .sunset, date: today, eventTime: sunsetToday)
        let fTomorrow = makeForecast(eventType: .sunset, date: tomorrow, eventTime: sunsetTomorrow)

        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: now.addingTimeInterval(-300),
            lastAttemptAt: now.addingTimeInterval(-300),
            forecasts: [fToday, fTomorrow],
            status: .current
        )

        XCTAssertTrue(snapshot.hasOperationalCoverage(for: location, now: now))
    }

    // F. After today's sunset, resolver selects tomorrow's sunrise from a two-day cache.
    func testAfterSunsetResolverSelectsTomorrowSunriseFromTwoDayCache() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneNY
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 0, minute: 0))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 0, minute: 0))!

        let sunsetTodayTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 19, minute: 50))!
        let sunriseTomorrowTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 6, minute: 15))!
        let sunsetTomorrowTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 19, minute: 48))!

        let location = makeLocation(forecastDays: 1, sunrise: true, sunset: true)
        let fSunsetToday = makeForecast(eventType: .sunset, date: today, eventTime: sunsetTodayTime)
        let fSunriseTomorrow = makeForecast(eventType: .sunrise, date: tomorrow, eventTime: sunriseTomorrowTime)
        let fSunsetTomorrow = makeForecast(eventType: .sunset, date: tomorrow, eventTime: sunsetTomorrowTime)

        let afterSunsetNow = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 20, minute: 30))!

        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: today,
            lastAttemptAt: today,
            forecasts: [fSunsetToday, fSunriseTomorrow, fSunsetTomorrow],
            status: .current
        )

        let resolved = MenuBarForecastResolver.resolve(
            location: location,
            snapshot: snapshot,
            selection: .nextEvent,
            now: afterSunsetNow
        )

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.eventType, .sunrise)
        XCTAssertEqual(resolved?.eventTime, sunriseTomorrowTime)
    }

    // G. After today's sunset, resolver selects tomorrow's sunset if menu-bar selection == nextSunset.
    func testAfterSunsetResolverSelectsTomorrowSunsetWhenSelectionIsNextSunset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneNY
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 0, minute: 0))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 0, minute: 0))!

        let sunsetTodayTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 19, minute: 50))!
        let sunriseTomorrowTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 6, minute: 15))!
        let sunsetTomorrowTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 19, minute: 48))!

        let location = makeLocation(forecastDays: 1, sunrise: true, sunset: true)
        let fSunsetToday = makeForecast(eventType: .sunset, date: today, eventTime: sunsetTodayTime)
        let fSunriseTomorrow = makeForecast(eventType: .sunrise, date: tomorrow, eventTime: sunriseTomorrowTime)
        let fSunsetTomorrow = makeForecast(eventType: .sunset, date: tomorrow, eventTime: sunsetTomorrowTime)

        let afterSunsetNow = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 20, minute: 30))!

        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: today,
            lastAttemptAt: today,
            forecasts: [fSunsetToday, fSunriseTomorrow, fSunsetTomorrow],
            status: .current
        )

        let resolved = MenuBarForecastResolver.resolve(
            location: location,
            snapshot: snapshot,
            selection: .nextSunset,
            now: afterSunsetNow
        )

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.eventType, .sunset)
        XCTAssertEqual(resolved?.eventTime, sunsetTomorrowTime)
    }

    // H. Different location timezones evaluate day coverage correctly.
    func testDifferentLocationTimezonesEvaluateDayCoverageCorrectly() {
        var calendarTokyo = Calendar(identifier: .gregorian)
        calendarTokyo.timeZone = timeZoneTokyo

        // When it is Aug 20 20:00 in NY (UTC Aug 21 00:00), in Tokyo it is Aug 21 09:00.
        let now = Date(timeIntervalSince1970: 1787270400) // Aug 21, 2026 00:00 UTC

        let locationTokyo = makeLocation(forecastDays: 1, timeZone: timeZoneTokyo, sunrise: false, sunset: true)

        let tokyoToday = calendarTokyo.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 0, minute: 0))!
        let tokyoTomorrow = calendarTokyo.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 0, minute: 0))!

        let fTokyoToday = makeForecast(eventType: .sunset, date: tokyoToday, eventTime: tokyoToday.addingTimeInterval(18 * 3600))
        let fTokyoTomorrow = makeForecast(eventType: .sunset, date: tokyoTomorrow, eventTime: tokyoTomorrow.addingTimeInterval(18 * 3600))

        // Snapshot with only Tokyo Aug 21 (today in Tokyo) lacks Tokyo Aug 22 (tomorrow in Tokyo)
        let partialSnapshot = CachedLocationSnapshot(
            locationID: locationTokyo.id,
            fetchedAt: now,
            lastAttemptAt: now,
            forecasts: [fTokyoToday],
            status: .current
        )
        XCTAssertFalse(partialSnapshot.hasOperationalCoverage(for: locationTokyo, now: now))

        // Snapshot with both Tokyo Aug 21 and Aug 22 has operational coverage
        let fullSnapshot = CachedLocationSnapshot(
            locationID: locationTokyo.id,
            fetchedAt: now,
            lastAttemptAt: now,
            forecasts: [fTokyoToday, fTokyoTomorrow],
            status: .current
        )
        XCTAssertTrue(fullSnapshot.hasOperationalCoverage(for: locationTokyo, now: now))
    }

    // I. A recently fetched current cache with insufficient horizon is selected for automatic refresh.
    func testRecentlyFetchedCacheWithInsufficientHorizonIsSelectedForRefresh() async throws {
        let location = makeLocation(forecastDays: 1, sunrise: false, sunset: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneNY
        let today = calendar.startOfDay(for: now)
        let sunsetToday = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: today) ?? today.addingTimeInterval(19 * 3600)
        let fToday = makeForecast(eventType: .sunset, date: today, eventTime: sunsetToday)

        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: now.addingTimeInterval(-60), // Fetched only 1 minute ago!
            lastAttemptAt: now.addingTimeInterval(-60),
            forecasts: [fToday], // Only 1 day
            status: .current
        )

        let body = try loadFixture("event_full")
        let transport = MockHTTPTransport(stubs: [
            .init(statusCode: 200, body: body),
            .init(statusCode: 200, body: body),
        ])
        let service = ForecastService(transport: transport)
        let settings = InMemorySettingsStore(state: SharedAppState(locations: [location]))
        let cache = InMemoryForecastCache(snapshots: [location.id: snapshot])
        let credentials = InMemoryCredentialStore(apiKey: "test-key")

        let coordinator = ForecastRefreshCoordinator(
            settingsStore: settings,
            forecastCache: cache,
            credentialStore: credentials,
            forecastService: service
        )

        // Non-forced refresh on a stale/insufficient cache should trigger a refresh
        let updated = await coordinator.refreshLocation(id: location.id, force: false)

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(updated?.forecasts.count, 2)
    }

    // J. A recently fetched current cache with sufficient two-day coverage is NOT gratuitously refreshed.
    func testRecentlyFetchedCacheWithSufficientCoverageIsNotGratuitouslyRefreshed() async throws {
        let location = makeLocation(forecastDays: 1, sunrise: false, sunset: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneNY
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let sunsetToday = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: today) ?? today.addingTimeInterval(19 * 3600)
        let sunsetTomorrow = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: tomorrow) ?? tomorrow.addingTimeInterval(19 * 3600)

        let fToday = makeForecast(eventType: .sunset, date: today, eventTime: sunsetToday)
        let fTomorrow = makeForecast(eventType: .sunset, date: tomorrow, eventTime: sunsetTomorrow)

        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: now.addingTimeInterval(-60), // 1 minute ago
            lastAttemptAt: now.addingTimeInterval(-60),
            forecasts: [fToday, fTomorrow], // 2 days present
            status: .current
        )

        let transport = MockHTTPTransport()
        let service = ForecastService(transport: transport)
        let settings = InMemorySettingsStore(state: SharedAppState(locations: [location]))
        let cache = InMemoryForecastCache(snapshots: [location.id: snapshot])
        let credentials = InMemoryCredentialStore(apiKey: "test-key")

        let coordinator = ForecastRefreshCoordinator(
            settingsStore: settings,
            forecastCache: cache,
            credentialStore: credentials,
            forecastService: service
        )

        let result = await coordinator.refreshLocation(id: location.id, force: false)

        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertEqual(result?.fetchedAt, snapshot.fetchedAt)
    }

    // K. Rate-limited cache with insufficient coverage still respects Retry-After.
    func testRateLimitedCacheWithInsufficientCoverageStillRespectsRetryAfter() async throws {
        let location = makeLocation(forecastDays: 1, sunrise: false, sunset: true)
        let now = Date()
        let retryAfterDate = now.addingTimeInterval(1800) // 30 minutes in future

        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: now.addingTimeInterval(-3600),
            lastAttemptAt: now,
            forecasts: [], // Empty/insufficient
            status: .rateLimited(retryAfter: retryAfterDate),
            nextAttemptAt: retryAfterDate
        )

        let transport = MockHTTPTransport()
        let service = ForecastService(transport: transport)
        let settings = InMemorySettingsStore(state: SharedAppState(locations: [location]))
        let cache = InMemoryForecastCache(snapshots: [location.id: snapshot])
        let credentials = InMemoryCredentialStore(apiKey: "test-key")

        let coordinator = ForecastRefreshCoordinator(
            settingsStore: settings,
            forecastCache: cache,
            credentialStore: credentials,
            forecastService: service
        )

        // Non-forced refresh should be skipped
        let nonForcedResult = await coordinator.refreshLocation(id: location.id, force: false)
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertEqual(nonForcedResult?.status, .rateLimited(retryAfter: retryAfterDate))

        // Forced refresh should also respect active Retry-After
        let forcedResult = await coordinator.refreshLocation(id: location.id, force: true)
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertEqual(forcedResult?.status, .rateLimited(retryAfter: retryAfterDate))
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }
}
