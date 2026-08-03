import XCTest
@testable import SunsetHueCore

final class RefreshBackoffTests: XCTestCase {
    func testTemporaryUnavailableUsesExponentialLadder() {
        let id = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let first = RefreshBackoff.nextAttempt(
            status: .temporarilyUnavailable,
            previousFailureCount: 0,
            locationID: id,
            from: start
        )
        XCTAssertEqual(first.consecutiveFailureCount, 1)
        XCTAssertEqual(first.nextAttemptAt?.timeIntervalSince(start), 15 * 60)

        let second = RefreshBackoff.nextAttempt(
            status: .temporarilyUnavailable,
            previousFailureCount: 1,
            locationID: id,
            from: start
        )
        XCTAssertEqual(second.nextAttemptAt?.timeIntervalSince(start), 30 * 60)

        let capped = RefreshBackoff.nextAttempt(
            status: .temporarilyUnavailable,
            previousFailureCount: 10,
            locationID: id,
            from: start
        )
        XCTAssertEqual(capped.nextAttemptAt?.timeIntervalSince(start), 2 * 60 * 60)
    }

    func testAuthenticationAndInvalidRequestDoNotScheduleRetry() {
        let id = UUID()
        let start = Date()
        for status: RefreshStatus in [.authenticationRequired, .invalidRequest] {
            let result = RefreshBackoff.nextAttempt(
                status: status,
                previousFailureCount: 2,
                locationID: id,
                from: start
            )
            XCTAssertNil(result.nextAttemptAt)
        }
    }

    func testSnapshotNextScheduledRefreshHonorsStatus() throws {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let auth = CachedLocationSnapshot(
            locationID: id,
            fetchedAt: now,
            lastAttemptAt: now,
            forecasts: [],
            status: .authenticationRequired
        )
        XCTAssertNil(auth.nextScheduledRefresh(refreshIntervalHours: 6, now: now))

        let current = CachedLocationSnapshot(
            locationID: id,
            fetchedAt: now,
            lastAttemptAt: now,
            forecasts: [],
            status: .current
        )
        let due = try XCTUnwrap(current.nextScheduledRefresh(refreshIntervalHours: 6, now: now))
        XCTAssertEqual(due.timeIntervalSince(now), 6 * 3600, accuracy: 1)
    }

    func testTimelineJitterIsDeterministicAcrossCalls() {
        let id = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let jitter = SunsetHueConstants.timelineJitterSeconds(for: id)
        XCTAssertEqual(jitter, SunsetHueConstants.timelineJitterSeconds(for: id))
        XCTAssertGreaterThanOrEqual(jitter, 0)
        XCTAssertLessThan(jitter, SunsetHueConstants.maxTimelineJitterSeconds)
        // Fixed expected value for FNV-1a over this UUID (must stay stable across processes).
        XCTAssertEqual(jitter, 881)
    }
}
