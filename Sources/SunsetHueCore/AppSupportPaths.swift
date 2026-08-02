import Foundation

public enum AppSupportPaths: Sendable {
    public static let settingsFileName = "app-state.json"
    public static let legacyCacheFileName = "forecast-cache.json"
    public static let cacheDirectoryName = "forecast-cache"

    public static func preferredContainerURL() -> URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SunsetHueConstants.appGroupIdentifier
        ) {
            return groupURL
        }
        // Fall back to legacy group for older signed installs mid-migration.
        if SunsetHueConstants.appGroupIdentifier != SunsetHueConstants.legacyAppGroupIdentifier,
           let legacyURL = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: SunsetHueConstants.legacyAppGroupIdentifier
           ) {
            return legacyURL
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("SunsetHue", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func settingsURL() -> URL {
        preferredContainerURL().appendingPathComponent(settingsFileName)
    }

    public static func cacheDirectoryURL() -> URL {
        let directory = preferredContainerURL().appendingPathComponent(cacheDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func cacheFileURL(for locationID: UUID) -> URL {
        cacheDirectoryURL().appendingPathComponent("\(locationID.uuidString).json")
    }

    public static func legacyCacheURL() -> URL {
        preferredContainerURL().appendingPathComponent(legacyCacheFileName)
    }

    /// Copies settings + legacy/per-location caches from the legacy App Group into the Team-ID group once.
    public static func migrateLegacyAppGroupContainerIfNeeded() {
        let modernID = SunsetHueConstants.appGroupIdentifier
        let legacyID = SunsetHueConstants.legacyAppGroupIdentifier
        guard modernID != legacyID else { return }
        guard let modern = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: modernID),
              let legacy = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: legacyID)
        else { return }

        let fm = FileManager.default
        try? fm.createDirectory(at: modern, withIntermediateDirectories: true)

        let modernSettings = modern.appendingPathComponent(settingsFileName)
        let legacySettings = legacy.appendingPathComponent(settingsFileName)
        if !fm.fileExists(atPath: modernSettings.path), fm.fileExists(atPath: legacySettings.path) {
            try? fm.copyItem(at: legacySettings, to: modernSettings)
        }

        let modernLegacyCache = modern.appendingPathComponent(legacyCacheFileName)
        let legacyLegacyCache = legacy.appendingPathComponent(legacyCacheFileName)
        if !fm.fileExists(atPath: modernLegacyCache.path), fm.fileExists(atPath: legacyLegacyCache.path) {
            try? fm.copyItem(at: legacyLegacyCache, to: modernLegacyCache)
        }

        let modernCacheDir = modern.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        let legacyCacheDir = legacy.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        if fm.fileExists(atPath: legacyCacheDir.path) {
            try? fm.createDirectory(at: modernCacheDir, withIntermediateDirectories: true)
            if let contents = try? fm.contentsOfDirectory(
                at: legacyCacheDir,
                includingPropertiesForKeys: nil
            ) {
                for file in contents where file.pathExtension == "json" {
                    let dest = modernCacheDir.appendingPathComponent(file.lastPathComponent)
                    if !fm.fileExists(atPath: dest.path) {
                        try? fm.copyItem(at: file, to: dest)
                    }
                }
            }
        }
    }
}
