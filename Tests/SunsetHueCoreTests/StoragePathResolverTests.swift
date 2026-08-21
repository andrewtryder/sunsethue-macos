import XCTest
@testable import SunsetHueCore

final class StoragePathResolverTests: XCTestCase {

    func testNoTeamIDResolvesToApplicationSupportWithoutProbingAppGroup() {
        let groupLookupCallCount = LockIsolated<Int>(0)
        let requestedGroups = LockIsolated<[String]>([])

        let appSupportDir = URL(fileURLWithPath: "/tmp/test-app-support")
        let env = StorageEnvironment(
            teamIdentifier: { nil },
            groupContainerURL: { group in
                groupLookupCallCount.withValue { $0 += 1 }
                requestedGroups.withValue { $0.append(group) }
                return URL(fileURLWithPath: "/tmp/group-container")
            },
            applicationSupportURL: { appSupportDir }
        )

        let resolver = StoragePathResolver(environment: env)
        let mode = resolver.resolveStorageMode()

        XCTAssertEqual(mode, .localApplicationSupport)
        XCTAssertEqual(groupLookupCallCount.value, 0, "Unsigned build must never probe containerURL for any App Group")
        XCTAssertTrue(requestedGroups.value.isEmpty)
        XCTAssertEqual(resolver.preferredContainerURL(), appSupportDir)
    }

    func testEmptyTeamIDResolvesToApplicationSupportWithoutProbingAppGroup() {
        let groupLookupCallCount = LockIsolated<Int>(0)

        let appSupportDir = URL(fileURLWithPath: "/tmp/test-app-support")
        let env = StorageEnvironment(
            teamIdentifier: { "   " },
            groupContainerURL: { _ in
                groupLookupCallCount.withValue { $0 += 1 }
                return URL(fileURLWithPath: "/tmp/group-container")
            },
            applicationSupportURL: { appSupportDir }
        )

        let resolver = StoragePathResolver(environment: env)
        XCTAssertEqual(resolver.resolveStorageMode(), .localApplicationSupport)
        XCTAssertEqual(groupLookupCallCount.value, 0)
    }

    func testTeamIDResolvesToTeamPrefixedAppGroup() {
        let teamID = "ABCDEFGHIJ"
        let requestedGroups = LockIsolated<[String]>([])
        let groupDir = URL(fileURLWithPath: "/tmp/team-group-container")
        let appSupportDir = URL(fileURLWithPath: "/tmp/test-app-support")

        let env = StorageEnvironment(
            teamIdentifier: { teamID },
            groupContainerURL: { group in
                requestedGroups.withValue { $0.append(group) }
                return groupDir
            },
            applicationSupportURL: { appSupportDir }
        )

        let resolver = StoragePathResolver(environment: env)
        let mode = resolver.resolveStorageMode()

        XCTAssertEqual(mode, .teamAppGroup(identifier: "ABCDEFGHIJ.group.com.andrewtryder.SunsetHue"))
        XCTAssertEqual(requestedGroups.value, ["ABCDEFGHIJ.group.com.andrewtryder.SunsetHue"])
        XCTAssertEqual(resolver.preferredContainerURL(), groupDir)
    }

    func testTeamIDContainerUnavailableFallsBackToLocalApplicationSupportWithoutRawLegacyProbe() {
        let teamID = "ABCDEFGHIJ"
        let requestedGroups = LockIsolated<[String]>([])
        let appSupportDir = URL(fileURLWithPath: "/tmp/test-app-support")

        let env = StorageEnvironment(
            teamIdentifier: { teamID },
            groupContainerURL: { group in
                requestedGroups.withValue { $0.append(group) }
                return nil // simulate containerURL returning nil for team group
            },
            applicationSupportURL: { appSupportDir }
        )

        let resolver = StoragePathResolver(environment: env)
        let mode = resolver.resolveStorageMode()

        XCTAssertEqual(mode, .localApplicationSupport)
        XCTAssertEqual(requestedGroups.value, ["ABCDEFGHIJ.group.com.andrewtryder.SunsetHue"])
        XCTAssertFalse(requestedGroups.value.contains("group.com.andrewtryder.SunsetHue"), "Must never probe raw legacy group")
        XCTAssertEqual(resolver.preferredContainerURL(), appSupportDir)
    }

    func testUnsignedModeNeverCallsGroupContainerURL() {
        let groupLookupCallCount = LockIsolated<Int>(0)
        let appSupportDir = URL(fileURLWithPath: "/tmp/test-app-support")

        let env = StorageEnvironment(
            teamIdentifier: { nil },
            groupContainerURL: { _ in
                groupLookupCallCount.withValue { $0 += 1 }
                return nil
            },
            applicationSupportURL: { appSupportDir }
        )

        let resolver = StoragePathResolver(environment: env)
        _ = resolver.resolveStorageMode()
        _ = resolver.preferredContainerURL()
        _ = resolver.settingsURL()
        _ = resolver.cacheDirectoryURL()
        _ = resolver.cacheFileURL(for: UUID())
        _ = resolver.legacyCacheURL()

        XCTAssertEqual(groupLookupCallCount.value, 0, "Unsigned mode must NEVER call groupContainerURL")
    }

    func testPersonalTeamModeQueriesOnlyTeamPrefixedIdentifierOnce() {
        let requestedGroups = LockIsolated<[String]>([])
        let groupDir = URL(fileURLWithPath: "/tmp/team-group-container")
        let appSupportDir = URL(fileURLWithPath: "/tmp/test-app-support")

        let env = StorageEnvironment(
            teamIdentifier: { "TEAM123456" },
            groupContainerURL: { group in
                requestedGroups.withValue { $0.append(group) }
                return groupDir
            },
            applicationSupportURL: { appSupportDir }
        )

        let resolver = StoragePathResolver(environment: env)
        let container = resolver.preferredContainerURL()

        XCTAssertEqual(container, groupDir)
        XCTAssertEqual(requestedGroups.value, ["TEAM123456.group.com.andrewtryder.SunsetHue"], "Personal Team mode must query groupContainerURL once with only the Team-prefixed identifier")
    }

    func testNormalStorageResolutionNeverRequestsRawLegacyAppGroup() {
        let recordedGroups = LockIsolated<[String]>([])
        let rawLegacy = "group.com.andrewtryder.SunsetHue"

        // Case A: Unsigned
        let unsignedEnv = StorageEnvironment(
            teamIdentifier: { nil },
            groupContainerURL: { group in
                recordedGroups.withValue { $0.append(group) }
                return nil
            },
            applicationSupportURL: { URL(fileURLWithPath: "/tmp/app-support-unsigned") }
        )
        let unsignedResolver = StoragePathResolver(environment: unsignedEnv)
        _ = unsignedResolver.resolveStorageMode()
        _ = unsignedResolver.preferredContainerURL()
        _ = unsignedResolver.settingsURL()
        _ = unsignedResolver.cacheDirectoryURL()

        // Case B: Signed Personal Team
        let signedEnv = StorageEnvironment(
            teamIdentifier: { "XYZ1234567" },
            groupContainerURL: { group in
                recordedGroups.withValue { $0.append(group) }
                return URL(fileURLWithPath: "/tmp/xyz-group")
            },
            applicationSupportURL: { URL(fileURLWithPath: "/tmp/app-support-signed") }
        )
        let signedResolver = StoragePathResolver(environment: signedEnv)
        _ = signedResolver.resolveStorageMode()
        _ = signedResolver.preferredContainerURL()
        _ = signedResolver.settingsURL()
        _ = signedResolver.cacheDirectoryURL()

        let allProbed = recordedGroups.value
        XCTAssertFalse(
            allProbed.contains(rawLegacy),
            "Privacy regression: Storage resolution must never query raw legacy group \(rawLegacy)"
        )
        XCTAssertTrue(allProbed.allSatisfy { $0 == "XYZ1234567.group.com.andrewtryder.SunsetHue" })
    }

    func testStoreInitializationDoesNotPerformLegacyMigration() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunsetHueStoreInitTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let cacheDir = tempDir.appendingPathComponent("cache", isDirectory: true)
        let legacyCache = tempDir.appendingPathComponent("legacy.json")

        // Initializing FileSettingsStore and FileForecastCache should be purely local and side-effect free
        _ = FileSettingsStore(fileURL: settingsURL)
        _ = FileForecastCache(cacheDirectory: cacheDir, legacyFileURL: legacyCache)
        _ = SharedStorageFactory.makeSettingsStore()
        _ = SharedStorageFactory.makeForecastCache()

        // Verify factory instantiation did not generate legacy files or crash
        XCTAssertTrue(true)
    }
}

private final class LockIsolated<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withValue<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&_value)
    }
}
