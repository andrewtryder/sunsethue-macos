import Foundation

public enum StorageMode: Equatable, Sendable {
    case localApplicationSupport
    case teamAppGroup(identifier: String)
}

public struct StorageEnvironment: Sendable {
    public var teamIdentifier: @Sendable () -> String?
    public var groupContainerURL: @Sendable (String) -> URL?
    public var applicationSupportURL: @Sendable () -> URL

    public init(
        teamIdentifier: @escaping @Sendable () -> String?,
        groupContainerURL: @escaping @Sendable (String) -> URL?,
        applicationSupportURL: @escaping @Sendable () -> URL
    ) {
        self.teamIdentifier = teamIdentifier
        self.groupContainerURL = groupContainerURL
        self.applicationSupportURL = applicationSupportURL
    }

    public static let live = StorageEnvironment(
        teamIdentifier: { SunsetHueConstants.teamIdentifier },
        groupContainerURL: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) },
        applicationSupportURL: {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return support.appendingPathComponent("SunsetHue", isDirectory: true)
        }
    )
}

public struct StoragePathResolver: Sendable {
    public let environment: StorageEnvironment

    public init(environment: StorageEnvironment = .live) {
        self.environment = environment
    }

    public func resolveContainerURL() -> (mode: StorageMode, url: URL) {
        guard let rawTeamID = environment.teamIdentifier()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTeamID.isEmpty else {
            let local = environment.applicationSupportURL()
            try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            return (.localApplicationSupport, local)
        }
        let groupID = SunsetHueConstants.teamAppGroupIdentifier(teamID: rawTeamID)
        if let groupURL = environment.groupContainerURL(groupID) {
            try? FileManager.default.createDirectory(at: groupURL, withIntermediateDirectories: true)
            return (.teamAppGroup(identifier: groupID), groupURL)
        }
        let local = environment.applicationSupportURL()
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        return (.localApplicationSupport, local)
    }

    public func resolveStorageMode() -> StorageMode {
        resolveContainerURL().mode
    }

    public func preferredContainerURL() -> URL {
        resolveContainerURL().url
    }

    public func settingsURL() -> URL {
        preferredContainerURL().appendingPathComponent(AppSupportPaths.settingsFileName)
    }

    public func cacheDirectoryURL() -> URL {
        let directory = preferredContainerURL().appendingPathComponent(AppSupportPaths.cacheDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func cacheFileURL(for locationID: UUID) -> URL {
        cacheDirectoryURL().appendingPathComponent("\(locationID.uuidString).json")
    }

    public func legacyCacheURL() -> URL {
        preferredContainerURL().appendingPathComponent(AppSupportPaths.legacyCacheFileName)
    }
}

public enum AppSupportPaths: Sendable {
    public static let settingsFileName = "app-state.json"
    public static let legacyCacheFileName = "forecast-cache.json"
    public static let cacheDirectoryName = "forecast-cache"

    public static func currentStorageMode() -> StorageMode {
        StoragePathResolver().resolveStorageMode()
    }

    public static func preferredContainerURL() -> URL {
        StoragePathResolver().preferredContainerURL()
    }

    public static func settingsURL() -> URL {
        StoragePathResolver().settingsURL()
    }

    public static func cacheDirectoryURL() -> URL {
        StoragePathResolver().cacheDirectoryURL()
    }

    public static func cacheFileURL(for locationID: UUID) -> URL {
        StoragePathResolver().cacheFileURL(for: locationID)
    }

    public static func legacyCacheURL() -> URL {
        StoragePathResolver().legacyCacheURL()
    }

    public struct StorageMigrationResult: Sendable, Equatable {
        public var copiedSettings: Bool
        public var copiedLegacyCache: Bool
        public var copiedCacheFileCount: Int

        public init(copiedSettings: Bool, copiedLegacyCache: Bool, copiedCacheFileCount: Int) {
            self.copiedSettings = copiedSettings
            self.copiedLegacyCache = copiedLegacyCache
            self.copiedCacheFileCount = copiedCacheFileCount
        }
    }

    /// Explicit, idempotent migration copying data from local Application Support (~/Library/Application Support/SunsetHue/)
    /// into the resolved Team App Group. Runs in the main app bootstrap only. Never touches Keychain or legacy raw groups.
    @discardableResult
    public static func migrateUnsignedStorageToTeamGroupIfNeeded(
        fileManager: FileManager = .default,
        resolver: StoragePathResolver = StoragePathResolver()
    ) -> StorageMigrationResult {
        guard case .teamAppGroup(let groupID) = resolver.resolveStorageMode(),
              let targetURL = resolver.environment.groupContainerURL(groupID) else {
            return StorageMigrationResult(copiedSettings: false, copiedLegacyCache: false, copiedCacheFileCount: 0)
        }
        let sourceURL = resolver.environment.applicationSupportURL()
        guard fileManager.fileExists(atPath: sourceURL.path), sourceURL.standardizedFileURL != targetURL.standardizedFileURL else {
            return StorageMigrationResult(copiedSettings: false, copiedLegacyCache: false, copiedCacheFileCount: 0)
        }

        try? fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)

        var copiedSettings = false
        var copiedLegacyCache = false
        var copiedCacheCount = 0

        // 1. Settings file: app-state.json
        let sourceSettings = sourceURL.appendingPathComponent(settingsFileName)
        let targetSettings = targetURL.appendingPathComponent(settingsFileName)
        if fileManager.fileExists(atPath: sourceSettings.path) && !fileManager.fileExists(atPath: targetSettings.path) {
            do {
                try fileManager.copyItem(at: sourceSettings, to: targetSettings)
                copiedSettings = true
            } catch {}
        }

        // 2. Legacy cache: forecast-cache.json
        let sourceLegacyCache = sourceURL.appendingPathComponent(legacyCacheFileName)
        let targetLegacyCache = targetURL.appendingPathComponent(legacyCacheFileName)
        if fileManager.fileExists(atPath: sourceLegacyCache.path) && !fileManager.fileExists(atPath: targetLegacyCache.path) {
            do {
                try fileManager.copyItem(at: sourceLegacyCache, to: targetLegacyCache)
                copiedLegacyCache = true
            } catch {}
        }

        // 3. Per-location cache directory: forecast-cache/
        let sourceCacheDir = sourceURL.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        let targetCacheDir = targetURL.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: sourceCacheDir.path) {
            try? fileManager.createDirectory(at: targetCacheDir, withIntermediateDirectories: true)
            if let contents = try? fileManager.contentsOfDirectory(
                at: sourceCacheDir,
                includingPropertiesForKeys: nil
            ) {
                for file in contents where file.pathExtension == "json" {
                    let dest = targetCacheDir.appendingPathComponent(file.lastPathComponent)
                    if !fileManager.fileExists(atPath: dest.path) {
                        do {
                            try fileManager.copyItem(at: file, to: dest)
                            copiedCacheCount += 1
                        } catch {}
                    }
                }
            }
        }

        return StorageMigrationResult(
            copiedSettings: copiedSettings,
            copiedLegacyCache: copiedLegacyCache,
            copiedCacheFileCount: copiedCacheCount
        )
    }
}
