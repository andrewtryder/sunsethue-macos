import XCTest
@testable import SunsetHueCore

final class Diagnostics13Tests: XCTestCase {
    func testRefreshActivityRecorderBoundedCapacity() async {
        let recorder = RefreshActivityRecorder(maxEntries: 50)
        let locationID = UUID()

        for i in 1...60 {
            await recorder.record(
                locationID: locationID,
                locationName: "Location \(i)",
                trigger: .scheduled,
                result: .refreshedSuccessfully,
                details: "Run \(i)"
            )
        }

        let entries = await recorder.recentEntries()
        XCTAssertEqual(entries.count, 50)
        // Newest entry first
        XCTAssertEqual(entries.first?.locationName, "Location 60")
        XCTAssertEqual(entries.first?.details, "Run 60")
        // Oldest preserved entry is #11
        XCTAssertEqual(entries.last?.locationName, "Location 11")
        XCTAssertEqual(entries.last?.details, "Run 11")
    }

    func testCoverageDiagnosticsDescriptions() {
        let location = PreviewFixtures.sampleLocation
        let now = Date()

        // Nil snapshot
        let emptyDesc = CoverageDiagnostics.coverageDescription(for: location, snapshot: nil, now: now)
        XCTAssertEqual(emptyDesc, "No forecast cached")

        // Snapshot with full coverage
        let bundle = PreviewFixtures.sampleBundle(fetchedAt: now)
        let fullSnap = CachedLocationSnapshot.fromSuccessful(bundle: bundle)
        let fullDesc = CoverageDiagnostics.coverageDescription(for: location, snapshot: fullSnap, now: now)
        XCTAssertTrue(fullDesc == "Today + Tomorrow" || fullDesc == "Today only" || fullDesc.contains("Today"))

        // Snapshot with empty forecasts
        let emptySnap = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: now,
            lastAttemptAt: now,
            forecasts: [],
            status: .stale,
            nextAttemptAt: nil,
            consecutiveFailureCount: 1
        )
        let zeroDesc = CoverageDiagnostics.coverageDescription(for: location, snapshot: emptySnap, now: now)
        XCTAssertEqual(zeroDesc, "No forecast cached")
    }

    func testPlainTextDiagnosticsGenerationAndSecretRedaction() throws {
        let location = PreviewFixtures.sampleLocation
        let secretKey = "super-secret-production-api-key-12345"
        let now = Date()
        let snapshot = CachedLocationSnapshot.fromSuccessful(bundle: PreviewFixtures.sampleBundle(fetchedAt: now))

        let storageDiag = StorageDiagnostics(
            storageMode: .teamAppGroup(identifier: "TEAM123.group.com.andrewtryder.SunsetHue"),
            storageModeDisplayName: "Personal Team App Group",
            appGroupIdentifier: "TEAM123.group.com.andrewtryder.SunsetHue",
            isAppGroupAvailable: true,
            isSettingsReadable: true,
            isForecastCacheReadable: true,
            lastCacheCommit: now,
            lastWidgetReloadRequested: now
        )

        let bgDiag = BackgroundRefreshDiagnostics(
            isActive: true,
            schedulerName: "NSBackgroundActivityScheduler",
            intervalDescription: "~30 min",
            lastActivityAt: now,
            lastDisposition: "finished",
            isLaunchAtLoginEnabled: true
        )

        let record = RefreshActivityRecord(
            id: UUID(),
            timestamp: now,
            locationID: location.id,
            locationName: location.name,
            trigger: .manual,
            result: .refreshedSuccessfully,
            details: "Updated 2 forecasts"
        )

        let text = try DiagnosticsExporter().makePlainTextDiagnostics(
            state: SharedAppState(locations: [location], selectedLocationID: location.id),
            snapshots: [location.id: snapshot],
            storageDiagnostics: storageDiag,
            backgroundDiagnostics: bgDiag,
            recentActivity: [record],
            notificationPreferences: NotificationPreferences(),
            notificationAuthorization: "Authorized",
            apiKeyConfigured: true,
            apiKeyValueForRedactionTests: secretKey,
            appVersion: "1.3.0",
            build: "42",
            now: now
        )

        // Verify structure
        XCTAssertTrue(text.contains("SunsetHue Diagnostics"))
        XCTAssertTrue(text.contains("Storage Mode:"))
        XCTAssertTrue(text.contains("Background Refresh:"))
        XCTAssertTrue(text.contains("Locations (1):"))
        XCTAssertTrue(text.contains("Recent Activity (Newest First):"))

        // Verify accurate widget reload labeling
        XCTAssertTrue(text.contains("Last Widget Reload Requested:"))
        XCTAssertFalse(text.contains("Last widget updated:"))

        // Verify privacy & secret redaction
        XCTAssertFalse(text.contains(secretKey))
        XCTAssertFalse(text.contains("x-api-key"))
        XCTAssertFalse(text.contains("Authorization: Bearer"))
        XCTAssertFalse(text.contains("\(location.latitude)"))
        XCTAssertFalse(text.contains("\(location.longitude)"))
    }

    func testWidgetReloadStateTracker() {
        let tracker = WidgetReloadStateTracker.shared
        let beforeRequest = Date()
        tracker.recordReloadRequest()
        XCTAssertNotNil(tracker.lastReloadRequested)
        XCTAssertGreaterThanOrEqual(tracker.lastReloadRequested!, beforeRequest)

        let beforeCommit = Date()
        tracker.recordCacheCommit()
        XCTAssertNotNil(tracker.lastCacheCommit)
        XCTAssertGreaterThanOrEqual(tracker.lastCacheCommit!, beforeCommit)
    }

    func testCoordinatorRecordsRefreshActivity() async throws {
        let location = SavedLocation(
            id: PreviewFixtures.sampleLocationID,
            name: "Sample Harbor",
            latitude: 40.7128,
            longitude: -74.006,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 1,
            includeSunrise: false,
            includeSunset: true,
            refreshIntervalHours: 6
        )
        let settings = InMemorySettingsStore(state: SharedAppState(locations: [location], selectedLocationID: location.id))
        let cache = InMemoryForecastCache()
        let credentials = InMemoryCredentialStore(apiKey: "test-key")
        let recorder = RefreshActivityRecorder()

        let body = try loadFixture("event_full")
        let transport = MockHTTPTransport(stubs: Array(repeating: MockHTTPTransport.Stub(statusCode: 200, body: body), count: 10))

        let coordinator = ForecastRefreshCoordinator(
            settingsStore: settings,
            forecastCache: cache,
            credentialStore: credentials,
            forecastService: ForecastService(transport: transport),
            activityRecorder: recorder
        )

        _ = await coordinator.refreshLocation(id: location.id, force: true, trigger: .manual)

        let entries = await recorder.recentEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.locationID, location.id)
        XCTAssertEqual(entries.first?.trigger, .manual)
        XCTAssertEqual(entries.first?.result, .refreshedSuccessfully)
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }
}
