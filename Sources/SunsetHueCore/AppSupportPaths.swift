import Foundation

/// Shared on-disk locations.
/// Prefer the App Group container when sandboxed (required for WidgetKit).
/// Fall back to ~/Library/Application Support/SunsetHue for unsigned non-sandbox builds.
public enum AppSupportPaths: Sendable {
    public static let folderName = "SunsetHue"

    public static var rootDirectory: URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SunsetHueConstants.appGroupIdentifier
        ) {
            return groupURL.appendingPathComponent(folderName, isDirectory: true)
        }
        return applicationSupportDirectory
    }

    public static var appStateURL: URL {
        rootDirectory.appendingPathComponent("app-state.json", isDirectory: false)
    }

    public static var forecastCacheURL: URL {
        rootDirectory.appendingPathComponent("forecast-cache.json", isDirectory: false)
    }

    public static func ensureRootDirectory() throws {
        try migrateLegacySharedFilesIfNeeded()
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    public static var usesAppGroupContainer: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SunsetHueConstants.appGroupIdentifier
        ) != nil
    }

    /// Copy settings/cache from pre-Sequoia `group.*` containers or Application Support
    /// into the Team-ID-prefixed App Group the widget can actually read.
    public static func migrateLegacySharedFilesIfNeeded() throws {
        let fm = FileManager.default
        let destination = rootDirectory
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let destinations = [
            destination.appendingPathComponent("app-state.json"),
            destination.appendingPathComponent("forecast-cache.json")
        ]
        guard destinations.contains(where: { !fm.fileExists(atPath: $0.path) }) else {
            return
        }

        for sourceRoot in legacyRoots() {
            for fileName in ["app-state.json", "forecast-cache.json"] {
                let source = sourceRoot.appendingPathComponent(fileName)
                let target = destination.appendingPathComponent(fileName)
                guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) else {
                    continue
                }
                // Skip no-op when source is already the destination path.
                guard source.standardizedFileURL != target.standardizedFileURL else { continue }
                try? fm.copyItem(at: source, to: target)
            }
        }
    }

    private static var applicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func legacyRoots() -> [URL] {
        var roots: [URL] = []
        if let legacyGroup = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SunsetHueConstants.legacyAppGroupIdentifier
        ) {
            roots.append(legacyGroup.appendingPathComponent(folderName, isDirectory: true))
        }
        roots.append(applicationSupportDirectory)
        return roots
    }
}
