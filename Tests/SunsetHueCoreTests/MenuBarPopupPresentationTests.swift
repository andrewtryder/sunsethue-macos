@testable import SunsetHueCore
import XCTest

/// Regression coverage for the menu bar popup lifecycle logic that can be exercised
/// without a GUI session.
///
/// The original production bug — dismissing the popup quit the entire process — was
/// AppKit's `applicationShouldTerminateAfterLastWindowClosed` default (fixed in
/// `AppDelegate`). That delegate hook cannot run in unit tests; the manual matrix in
/// `docs/menubar-popup-testing.md` covers the interactive cases. These tests pin the
/// presentation-adjacent invariants: idempotent presentation state handling and
/// wake-time stability across the supported location counts.
final class MenuBarPopupPresentationTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 0)

    private func makeLocation(name: String, id: UUID = UUID()) -> SavedLocation {
        SavedLocation(
            id: id,
            name: name,
            latitude: 43.0,
            longitude: -71.0,
            timeZoneIdentifier: "America/New_York",
            includeSunrise: true,
            includeSunset: true
        )
    }

    // MARK: - Row coverage across location counts

    /// Popup row generation must be stable for zero, one, many, and >7 (scrollable)
    /// locations — the counts called out in the popup regression matrix.
    func testRowCountsAcrossLocationCounts() {
        let prefs = MenuBarPreferences()
        let now = Date()

        let zero = MenuBarPopoverPresenter.buildRows(
            locations: [], snapshots: [:], preferences: prefs, selectedLocationID: nil, now: now
        )
        XCTAssertEqual(zero.count, 0)

        let one = makeLocation(name: "Only")
        let rows1 = MenuBarPopoverPresenter.buildRows(
            locations: [one], snapshots: [:], preferences: prefs, selectedLocationID: one.id, now: now
        )
        XCTAssertEqual(rows1.count, 1)

        let several = (1 ... 5).map { makeLocation(name: "Loc \($0)") }
        let rows5 = MenuBarPopoverPresenter.buildRows(
            locations: several, snapshots: [:], preferences: prefs, selectedLocationID: several[2].id, now: now
        )
        XCTAssertEqual(rows5.count, 5)

        // More than maxVisibleRows (7): still one row per location; the view scrolls.
        let many = (1 ... 11).map { makeLocation(name: "Loc \($0)") }
        let rows11 = MenuBarPopoverPresenter.buildRows(
            locations: many, snapshots: [:], preferences: prefs, selectedLocationID: many[0].id, now: now
        )
        XCTAssertEqual(rows11.count, 11)
    }

    // MARK: - Wake scheduling while the popup is open

    /// With a single location the wake time must not depend on rotation state, so
    /// suspending the schedule while the popup is open never shifts the next wake.
    func testNextWakeDateIsStableForSingleLocation() {
        let location = makeLocation(name: "Solo")
        let prefs = MenuBarPreferences(locationMode: .rotateLocations)
        let now = Date()

        let wake = MenuBarRotationLogic.nextWakeDate(
            locations: [location],
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: location.id,
            now: now,
            epoch: epoch
        )
        XCTAssertEqual(wake.timeIntervalSince(now), 60, accuracy: 1.0)
    }

    /// Rotation mode with several locations always yields a finite wake in the future.
    func testNextWakeDateIsFiniteInRotationMode() {
        let locations = (1 ... 3).map { makeLocation(name: "Rot \($0)") }
        let prefs = MenuBarPreferences(locationMode: .rotateLocations, rotationIntervalSeconds: 5)
        let now = Date()

        let wake = MenuBarRotationLogic.nextWakeDate(
            locations: locations,
            snapshots: [:],
            preferences: prefs,
            selectedLocationID: nil,
            now: now,
            epoch: epoch
        )
        XCTAssertGreaterThan(wake, now)
        // Next 5s rotation tick or the 60s fallback poll — never further than the fallback.
        XCTAssertLessThanOrEqual(wake.timeIntervalSince(now), 61)
    }

    // MARK: - Label content stability

    /// Re-resolving with unchanged inputs must produce identical label content, which
    /// keeps `MenuBarLabelController` from emitting redundant `@Published` changes.
    func testLabelResolutionIsDeterministicForUnchangedInputs() {
        let location = makeLocation(name: "Stable")
        let prefs = MenuBarPreferences()
        let now = Date()

        let first = MenuBarRotationLogic.locationForLabel(
            locations: [location], snapshots: [:], preferences: prefs, selectedLocationID: location.id,
            now: now, epoch: epoch
        )
        let second = MenuBarRotationLogic.locationForLabel(
            locations: [location], snapshots: [:], preferences: prefs, selectedLocationID: location.id,
            now: now, epoch: epoch
        )
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(first?.name, second?.name)
    }
}
