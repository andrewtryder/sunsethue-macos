import XCTest
@testable import SunsetHueCore

final class ForecastFreshnessPresenterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private let locale = Locale(identifier: "en_US_POSIX")
    private let zone = TimeZone(identifier: "America/New_York")!

    private func location(interval: Int = 6) -> SavedLocation {
        SavedLocation(name: "Home", latitude: 40, longitude: -74, timeZoneIdentifier: "America/New_York",
                      forecastDays: 2, refreshIntervalHours: interval)
    }

    private func forecast(quality: Double? = 0.8) -> EventForecast {
        EventForecast(
            responseTime: now, location: Coordinates(latitude: 40, longitude: -74),
            gridLocation: Coordinates(latitude: 40, longitude: -74), eventType: .sunset,
            modelData: quality != nil, quality: quality, qualityText: quality == nil ? nil : "Good",
            cloudCover: 0.2, eventTime: now.addingTimeInterval(3600), direction: 270,
            blueHour: nil, goldenHour: nil, forecastDate: now
        )
    }

    private func snapshot(
        _ loc: SavedLocation,
        status: RefreshStatus,
        ageSeconds: TimeInterval,
        forecasts: [EventForecast]? = nil,
        nextAttempt: Date? = nil
    ) -> CachedLocationSnapshot {
        CachedLocationSnapshot(
            locationID: loc.id,
            fetchedAt: now.addingTimeInterval(-ageSeconds),
            lastAttemptAt: now.addingTimeInterval(-60),
            forecasts: forecasts ?? [forecast()],
            status: status,
            nextAttemptAt: nextAttempt,
            consecutiveFailureCount: status == .current ? 0 : 1
        )
    }

    private func describe(
        _ snap: CachedLocationSnapshot?,
        _ loc: SavedLocation,
        credentials: CredentialState = .configured,
        refreshing: Bool = false
    ) -> ForecastFreshness {
        ForecastFreshnessPresenter.describe(
            snapshot: snap, location: loc, credentialState: credentials,
            isRefreshing: refreshing, now: now, locale: locale, displayTimeZone: zone
        )
    }

    func testAgeText() {
        XCTAssertEqual(ForecastFreshnessPresenter.ageText(from: now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(ForecastFreshnessPresenter.ageText(from: now.addingTimeInterval(-12 * 60), now: now), "12 min ago")
        XCTAssertEqual(ForecastFreshnessPresenter.ageText(from: now.addingTimeInterval(-3 * 3600), now: now), "3 hr ago")
        XCTAssertEqual(ForecastFreshnessPresenter.ageText(from: now.addingTimeInterval(-86_400), now: now), "1 day ago")
        XCTAssertEqual(ForecastFreshnessPresenter.ageText(from: now.addingTimeInterval(-3 * 86_400), now: now), "3 days ago")
    }

    func testFreshCurrentForecastIsDescribedAsCurrent() {
        let loc = location()
        let result = describe(snapshot(loc, status: .current, ageSeconds: 600), loc)
        XCTAssertEqual(result.kind, .current)
        XCTAssertFalse(result.showsCachedForecast)
        XCTAssertFalse(result.needsAttention)
        XCTAssertEqual(result.ageText, "Updated 10 min ago")
    }

    func testOldCurrentSnapshotIsNeverDescribedAsCurrent() {
        let loc = location(interval: 6)
        let result = describe(snapshot(loc, status: .current, ageSeconds: 7 * 3600), loc)
        XCTAssertEqual(result.kind, .cachedAwaitingRefresh)
        XCTAssertTrue(result.showsCachedForecast)
        XCTAssertTrue(result.detail?.contains("7 hr ago") ?? false)
        XCTAssertNotEqual(result.headline, "Up to date")
    }

    func testNetworkFailureShowsCachedAgeAndRetry() {
        let loc = location()
        let snap = snapshot(loc, status: .temporarilyUnavailable, ageSeconds: 2 * 3600,
                            nextAttempt: now.addingTimeInterval(15 * 60))
        let result = describe(snap, loc)
        XCTAssertEqual(result.kind, .networkFailure)
        XCTAssertTrue(result.showsCachedForecast)
        XCTAssertTrue(result.detail?.contains("2 hr ago") ?? false)
        XCTAssertNotNil(result.nextRefreshText)
        XCTAssertTrue(result.needsAttention)
    }

    func testNetworkFailureWithoutCacheSaysSo() {
        let loc = location()
        let snap = snapshot(loc, status: .temporarilyUnavailable, ageSeconds: 0, forecasts: [],
                            nextAttempt: now.addingTimeInterval(900))
        let result = describe(snap, loc)
        XCTAssertFalse(result.showsCachedForecast)
        XCTAssertNil(result.ageText)
        XCTAssertTrue(result.detail?.contains("No saved forecast") ?? false)
    }

    func testAuthenticationMessagesDistinguishMissingRejectedAndKeychain() {
        let loc = location()
        let snap = snapshot(loc, status: .authenticationRequired, ageSeconds: 3600)
        XCTAssertTrue(describe(snap, loc, credentials: .missing).detail?.contains("Add your API key") ?? false)
        XCTAssertTrue(describe(snap, loc, credentials: .configured).detail?.contains("rejected the API key") ?? false)
        XCTAssertTrue(describe(snap, loc, credentials: .unavailable).detail?.contains("Keychain") ?? false)
        XCTAssertEqual(describe(snap, loc).kind, .authenticationRequired)
        XCTAssertNil(describe(snap, loc).nextRefreshText, "No automatic retry for auth failures")
    }

    func testRateLimitedMentionsDeadlineAndNeverClaimsCurrent() {
        let loc = location()
        let snap = snapshot(loc, status: .rateLimited(retryAfter: now.addingTimeInterval(1800)), ageSeconds: 3600)
        let result = describe(snap, loc)
        XCTAssertEqual(result.kind, .rateLimited)
        XCTAssertTrue(result.detail?.contains("Next attempt after") ?? false)
        XCTAssertTrue(result.showsCachedForecast)
    }

    func testModelDataUnavailableIsDistinctFromFailures() {
        let loc = location()
        let snap = snapshot(loc, status: .current, ageSeconds: 300, forecasts: [forecast(quality: nil)])
        let result = describe(snap, loc)
        XCTAssertEqual(result.kind, .modelUnavailable)
        XCTAssertFalse(result.needsAttention)
    }

    func testInvalidRequestAndResponseAreRejected() {
        let loc = location()
        XCTAssertEqual(describe(snapshot(loc, status: .invalidRequest, ageSeconds: 10), loc).kind, .rejected)
        XCTAssertEqual(describe(snapshot(loc, status: .invalidResponse, ageSeconds: 10), loc).kind, .rejected)
    }

    func testNoSnapshotStates() {
        let loc = location()
        XCTAssertEqual(describe(nil, loc, refreshing: true).kind, .loading)
        XCTAssertEqual(describe(nil, loc, credentials: .missing).kind, .authenticationRequired)
        XCTAssertEqual(describe(nil, loc).kind, .noData)
    }

    func testRefreshingFlagIsPropagated() {
        let loc = location()
        let result = describe(snapshot(loc, status: .current, ageSeconds: 60), loc, refreshing: true)
        XCTAssertTrue(result.isRefreshing)
    }
}

