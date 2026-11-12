import XCTest
@testable import SunsetHueCore

final class LegacyCacheMigrationHardeningTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunsetHueLegacyMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions so cleanup always succeeds.
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private var legacyURL: URL { root.appendingPathComponent("forecast-cache.json") }
    private var cacheDir: URL { root.appendingPathComponent("forecast-cache", isDirectory: true) }

    private func bundle(for id: UUID) -> LocationForecastBundle {
        let template = PreviewFixtures.sampleBundle()
        return LocationForecastBundle(locationID: id, fetchedAt: template.fetchedAt, forecasts: template.forecasts)
    }

    private func writeLegacy(_ ids: [UUID]) throws {
        let store = CachedForecastStore(bundles: Dictionary(uniqueKeysWithValues: ids.map { ($0, bundle(for: $0)) }))
        try JSONEncoder.sunsetHue.encode(store).write(to: legacyURL)
    }

    private func contents(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    func testSuccessfulMigrationReportsCompletionAndKeepsSourceAsBackup() async throws {
        let ids = [UUID(), UUID()]
        try writeLegacy(ids)
        let cache = FileForecastCache(rootDirectory: root)

        for id in ids {
            let loaded = try await cache.loadSnapshot(for: id)
            XCTAssertNotNil(loaded)
        }
        let report = await cache.lastLegacyMigrationReport
        XCTAssertEqual(report?.completed, true)
        XCTAssertEqual(Set(report?.migratedLocationIDs ?? []), Set(ids))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(contents(root).contains { $0.hasPrefix("forecast-cache.json.migrated-") },
                      "Source is renamed, not deleted")
    }

    func testPartialWriteFailureKeepsSourceAndRetrySucceeds() async throws {
        let ids = [UUID(), UUID()]
        try writeLegacy(ids)
        let cache = FileForecastCache(rootDirectory: root, legacyMigrationRetryInterval: 0)

        // Make the destination unwritable so every entry fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: cacheDir.path)
        _ = try await cache.loadSnapshot(for: ids[0])

        let failed = await cache.lastLegacyMigrationReport
        XCTAssertEqual(failed?.completed, false)
        XCTAssertEqual(Set(failed?.failedLocationIDs ?? []), Set(ids), "Failures must be detectable")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path), "Source preserved after failure")

        // Fix the condition; the next access retries and finishes.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cacheDir.path)
        let retried = try await cache.loadSnapshot(for: ids[1])
        XCTAssertNotNil(retried)
        let report = await cache.lastLegacyMigrationReport
        XCTAssertEqual(report?.completed, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        let other = try await cache.loadSnapshot(for: ids[0])
        XCTAssertNotNil(other)
    }

    func testInterruptedMigrationDoesNotOverwriteAlreadyMigratedItems() async throws {
        let done = UUID()
        let pending = UUID()
        try writeLegacy([done, pending])

        // Simulate a crash after `done` was written but before the source was set aside.
        let newer = CachedLocationSnapshot(
            locationID: done,
            fetchedAt: Date().addingTimeInterval(600),
            lastAttemptAt: Date().addingTimeInterval(600),
            forecasts: [],
            status: .current
        )
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try JSONEncoder.sunsetHue.encode(newer).write(to: cacheDir.appendingPathComponent("\(done.uuidString).json"))

        let cache = FileForecastCache(rootDirectory: root)
        let doneSnapshot = try await cache.loadSnapshot(for: done)
        XCTAssertEqual(doneSnapshot?.forecasts.count, 0, "Existing newer file must not be overwritten by legacy data")
        let pendingSnapshot = try await cache.loadSnapshot(for: pending)
        XCTAssertNotNil(pendingSnapshot)

        let report = await cache.lastLegacyMigrationReport
        XCTAssertEqual(report?.skippedExistingLocationIDs, [done])
        XCTAssertEqual(report?.migratedLocationIDs, [pending])
        XCTAssertEqual(report?.completed, true)
    }

    func testRepeatedMigrationIsIdempotent() async throws {
        let id = UUID()
        try writeLegacy([id])
        let first = FileForecastCache(rootDirectory: root)
        let a = try await first.loadSnapshot(for: id)
        XCTAssertNotNil(a)

        let second = FileForecastCache(rootDirectory: root)
        let b = try await second.loadSnapshot(for: id)
        XCTAssertEqual(a, b)
        let report = await second.lastLegacyMigrationReport
        XCTAssertNil(report, "Nothing left to migrate on later launches")
    }

    func testCorruptLegacyFileIsQuarantinedAndExistingDataSurvives() async throws {
        let existing = UUID()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let snapshot = CachedLocationSnapshot.fromSuccessful(bundle: bundle(for: existing))
        try JSONEncoder.sunsetHue.encode(snapshot).write(to: cacheDir.appendingPathComponent("\(existing.uuidString).json"))
        try Data("{ this is not json".utf8).write(to: legacyURL)

        let cache = FileForecastCache(rootDirectory: root)
        let loaded = try await cache.loadSnapshot(for: existing)
        XCTAssertNotNil(loaded)
        let report = await cache.lastLegacyMigrationReport
        XCTAssertEqual(report?.quarantinedCorruptSource, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(contents(root).contains { $0.hasPrefix("forecast-cache.json.corrupt-") })
    }

    func testUnreadableLegacySourceIsNotTreatedAsCorrupt() async throws {
        let id = UUID()
        try writeLegacy([id])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: legacyURL.path)

        let cache = FileForecastCache(rootDirectory: root, legacyMigrationRetryInterval: 0)
        let first = try await cache.loadSnapshot(for: id)
        XCTAssertNil(first)
        let report = await cache.lastLegacyMigrationReport
        XCTAssertEqual(report?.sourceUnreadable, true)
        XCTAssertFalse(contents(root).contains { $0.contains("corrupt") }, "I/O errors must not quarantine good data")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyURL.path)
        let second = try await cache.loadSnapshot(for: id)
        XCTAssertNotNil(second)
    }

    func testCorruptDestinationIsQuarantinedAndRestoredFromLegacy() async throws {
        let id = UUID()
        try writeLegacy([id])
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: cacheDir.appendingPathComponent("\(id.uuidString).json"))

        let cache = FileForecastCache(rootDirectory: root)
        let loaded = try await cache.loadSnapshot(for: id)
        XCTAssertNotNil(loaded)
        XCTAssertTrue(contents(cacheDir).contains { $0.contains(".corrupt-") })
    }

    // MARK: Application Support -> Team group copy

    func testTeamGroupMigrationReportsFailuresAndNeverDeletesSource() throws {
        let appSupport = root.appendingPathComponent("AppSupport", isDirectory: true)
        let group = root.appendingPathComponent("Group", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        let settingsSource = appSupport.appendingPathComponent("app-state.json")
        try Data("{}".utf8).write(to: settingsSource)

        let resolver = StoragePathResolver(environment: StorageEnvironment(
            teamIdentifier: { "TEAM123456" },
            groupContainerURL: { _ in group },
            applicationSupportURL: { appSupport }
        ))

        // Unwritable destination: copy must fail visibly.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: group.path)
        let failed = AppSupportPaths.migrateUnsignedStorageToTeamGroupIfNeeded(resolver: resolver)
        XCTAssertFalse(failed.isComplete)
        XCTAssertEqual(failed.failedItems, ["app-state.json"])
        XCTAssertFalse(failed.copiedSettings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsSource.path))
        XCTAssertFalse(contents(group).contains { $0.hasSuffix(".migrating") }, "No temp leftovers")

        // Retry after the condition clears.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: group.path)
        let retried = AppSupportPaths.migrateUnsignedStorageToTeamGroupIfNeeded(resolver: resolver)
        XCTAssertTrue(retried.isComplete)
        XCTAssertTrue(retried.copiedSettings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.appendingPathComponent("app-state.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsSource.path))
    }
}
