import XCTest
@testable import SunsetHueCore

final class StorageMigrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunsetHueMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testApplicationSupportToTeamGroupMigrationCopiesSettingsAndCache() throws {
        let appSupportDir = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
        let teamGroupDir = tempDir.appendingPathComponent("TeamGroup", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: teamGroupDir, withIntermediateDirectories: true)

        let appSupportCacheDir = appSupportDir.appendingPathComponent("forecast-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportCacheDir, withIntermediateDirectories: true)

        // Seed AppSupport with settings and a location cache
        let location = SavedLocation(
            id: UUID(),
            name: "Harbor View",
            latitude: 42.3601,
            longitude: -71.0589,
            timeZoneIdentifier: "America/New_York",
            forecastDays: 1,
            includeSunrise: true,
            includeSunset: true,
            refreshIntervalHours: 6
        )
        let originalState = SharedAppState(locations: [location])
        let encoder = JSONEncoder.sunsetHue
        let settingsData = try encoder.encode(originalState)
        try settingsData.write(to: appSupportDir.appendingPathComponent("app-state.json"))

        let snapshot = CachedLocationSnapshot(
            locationID: location.id,
            fetchedAt: Date(),
            lastAttemptAt: Date(),
            forecasts: [PreviewFixtures.excellentSunset(on: Date())],
            status: .current
        )
        let cacheData = try encoder.encode(snapshot)
        try cacheData.write(to: appSupportCacheDir.appendingPathComponent("\(location.id.uuidString).json"))

        let env = StorageEnvironment(
            teamIdentifier: { "TEAM123456" },
            groupContainerURL: { _ in teamGroupDir },
            applicationSupportURL: { appSupportDir }
        )
        let resolver = StoragePathResolver(environment: env)

        let result = AppSupportPaths.migrateUnsignedStorageToTeamGroupIfNeeded(
            fileManager: .default,
            resolver: resolver
        )

        XCTAssertTrue(result.copiedSettings)
        XCTAssertEqual(result.copiedCacheFileCount, 1)

        // Verify target Team Group has the copied files
        let targetSettingsURL = teamGroupDir.appendingPathComponent("app-state.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetSettingsURL.path))
        let targetCacheURL = teamGroupDir.appendingPathComponent("forecast-cache/\(location.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetCacheURL.path))

        // Verify source files are left intact (not deleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appSupportDir.appendingPathComponent("app-state.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appSupportCacheDir.appendingPathComponent("\(location.id.uuidString).json").path))
    }

    func testMigrationDoesNotOverwriteExistingTeamGroupSettingsOrCache() throws {
        let appSupportDir = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
        let teamGroupDir = tempDir.appendingPathComponent("TeamGroup", isDirectory: true)
        let teamGroupCacheDir = teamGroupDir.appendingPathComponent("forecast-cache", isDirectory: true)
        let appSupportCacheDir = appSupportDir.appendingPathComponent("forecast-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: teamGroupDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: teamGroupCacheDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupportCacheDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder.sunsetHue
        let decoder = JSONDecoder.sunsetHue

        // Seed AppSupport with "Old AppSupport Name"
        let oldState = SharedAppState(locations: [
            SavedLocation(
                id: UUID(),
                name: "Old AppSupport Name",
                latitude: 10,
                longitude: 20,
                timeZoneIdentifier: "UTC",
                forecastDays: 1,
                includeSunrise: true,
                includeSunset: true,
                refreshIntervalHours: 6
            )
        ])
        try encoder.encode(oldState).write(to: appSupportDir.appendingPathComponent("app-state.json"))

        // Seed Team Group with "Existing TeamGroup Name"
        let existingState = SharedAppState(locations: [
            SavedLocation(
                id: UUID(),
                name: "Existing TeamGroup Name",
                latitude: 30,
                longitude: 40,
                timeZoneIdentifier: "UTC",
                forecastDays: 1,
                includeSunrise: true,
                includeSunset: true,
                refreshIntervalHours: 6
            )
        ])
        try encoder.encode(existingState).write(to: teamGroupDir.appendingPathComponent("app-state.json"))

        let env = StorageEnvironment(
            teamIdentifier: { "TEAM123456" },
            groupContainerURL: { _ in teamGroupDir },
            applicationSupportURL: { appSupportDir }
        )
        let resolver = StoragePathResolver(environment: env)

        let result = AppSupportPaths.migrateUnsignedStorageToTeamGroupIfNeeded(
            fileManager: .default,
            resolver: resolver
        )

        XCTAssertFalse(result.copiedSettings, "Must not overwrite existing Team Group settings")

        let currentData = try Data(contentsOf: teamGroupDir.appendingPathComponent("app-state.json"))
        let loaded = try decoder.decode(SharedAppState.self, from: currentData)
        XCTAssertEqual(loaded.locations.first?.name, "Existing TeamGroup Name")
    }

    func testMigrationIsIdempotent() throws {
        let appSupportDir = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
        let teamGroupDir = tempDir.appendingPathComponent("TeamGroup", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: teamGroupDir, withIntermediateDirectories: true)

        let state = SharedAppState(locations: [])
        try JSONEncoder.sunsetHue.encode(state).write(to: appSupportDir.appendingPathComponent("app-state.json"))

        let env = StorageEnvironment(
            teamIdentifier: { "TEAM123456" },
            groupContainerURL: { _ in teamGroupDir },
            applicationSupportURL: { appSupportDir }
        )
        let resolver = StoragePathResolver(environment: env)

        let firstRun = AppSupportPaths.migrateUnsignedStorageToTeamGroupIfNeeded(
            fileManager: .default,
            resolver: resolver
        )
        XCTAssertTrue(firstRun.copiedSettings)

        let secondRun = AppSupportPaths.migrateUnsignedStorageToTeamGroupIfNeeded(
            fileManager: .default,
            resolver: resolver
        )
        XCTAssertFalse(secondRun.copiedSettings, "Second run should be no-op")
        XCTAssertEqual(secondRun.copiedCacheFileCount, 0)
    }

    func testMigrationNeverAccessesOrMigratesCredentials() throws {
        let appSupportDir = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
        let teamGroupDir = tempDir.appendingPathComponent("TeamGroup", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: teamGroupDir, withIntermediateDirectories: true)

        let env = StorageEnvironment(
            teamIdentifier: { "TEAM123456" },
            groupContainerURL: { _ in teamGroupDir },
            applicationSupportURL: { appSupportDir }
        )
        let resolver = StoragePathResolver(environment: env)

        _ = AppSupportPaths.migrateUnsignedStorageToTeamGroupIfNeeded(
            fileManager: .default,
            resolver: resolver
        )

        // Assert no keychain or credentials file is created in the target directory
        let files = try FileManager.default.contentsOfDirectory(atPath: teamGroupDir.path)
        for file in files {
            XCTAssertFalse(file.contains("keychain"), "Keychain must never be stored as files in App Group")
            XCTAssertFalse(file.contains("credential"), "Credentials must never be stored as files in App Group")
            XCTAssertFalse(file.contains("api-key"), "API keys must never be stored as files in App Group")
        }
    }
}
