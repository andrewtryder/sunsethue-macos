import Foundation

public protocol SharedSettingsStore: Sendable {
    func load() async throws -> SharedAppState
    func save(_ state: SharedAppState) async throws
}

public protocol ForecastCache: Sendable {
    func loadSnapshot(for locationID: UUID) async throws -> CachedLocationSnapshot?
    func loadBundle(for locationID: UUID) async throws -> LocationForecastBundle?
    func saveSnapshot(_ snapshot: CachedLocationSnapshot) async throws
    func deleteLocation(_ locationID: UUID) async throws
}

public actor FileSettingsStore: SharedSettingsStore {
    private let fileURL: URL
    private let encoder = JSONEncoder.sunsetHue
    private let decoder = JSONDecoder.sunsetHue

    public init(fileURL: URL = AppSupportPaths.settingsURL()) {
        self.fileURL = fileURL
        AppSupportPaths.migrateLegacyAppGroupContainerIfNeeded()
    }

    public func load() async throws -> SharedAppState {
        do {
            guard let data = try CoordinatedFileIO.readData(
                from: fileURL,
                maxBytes: SunsetHueConstants.maxSettingsFileBytes
            ) else {
                return SharedAppState()
            }
            return try decoder.decode(SharedAppState.self, from: data)
        } catch is DecodingError {
            CoordinatedFileIO.quarantineCorruptFile(at: fileURL)
            return SharedAppState()
        } catch SunsetHueError.storageTooLarge {
            CoordinatedFileIO.quarantineCorruptFile(at: fileURL)
            return SharedAppState()
        }
    }

    public func save(_ state: SharedAppState) async throws {
        var normalized = state
        normalized.schemaVersion = SunsetHueConstants.currentSettingsSchemaVersion
        let data = try encoder.encode(normalized)
        guard data.count <= SunsetHueConstants.maxSettingsFileBytes else {
            throw SunsetHueError.storageTooLarge
        }
        try CoordinatedFileIO.writeAtomically(data, to: fileURL)
    }
}

public actor FileForecastCache: ForecastCache {
    private let cacheDirectory: URL
    private let legacyFileURL: URL
    private let encoder = JSONEncoder.sunsetHue
    private let decoder = JSONDecoder.sunsetHue
    private var didMigrateLegacy = false

    public init(
        cacheDirectory: URL = AppSupportPaths.cacheDirectoryURL(),
        legacyFileURL: URL = AppSupportPaths.legacyCacheURL()
    ) {
        self.cacheDirectory = cacheDirectory
        self.legacyFileURL = legacyFileURL
        AppSupportPaths.migrateLegacyAppGroupContainerIfNeeded()
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public init(rootDirectory: URL) {
        self.cacheDirectory = rootDirectory.appendingPathComponent(
            AppSupportPaths.cacheDirectoryName,
            isDirectory: true
        )
        self.legacyFileURL = rootDirectory.appendingPathComponent(AppSupportPaths.legacyCacheFileName)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func loadSnapshot(for locationID: UUID) async throws -> CachedLocationSnapshot? {
        try migrateLegacyIfNeeded()
        let url = fileURL(for: locationID)
        do {
            guard let data = try CoordinatedFileIO.readData(
                from: url,
                maxBytes: SunsetHueConstants.maxCacheFileBytes
            ) else {
                return nil
            }
            var snapshot = try decoder.decode(CachedLocationSnapshot.self, from: data)
            if snapshot.locationID != locationID {
                snapshot = CachedLocationSnapshot(
                    schemaVersion: SunsetHueConstants.currentCacheSchemaVersion,
                    locationID: locationID,
                    fetchedAt: snapshot.fetchedAt,
                    lastAttemptAt: snapshot.lastAttemptAt,
                    forecasts: snapshot.forecasts,
                    status: snapshot.status
                )
            }
            return snapshot
        } catch is DecodingError {
            CoordinatedFileIO.quarantineCorruptFile(at: url)
            return nil
        } catch SunsetHueError.storageTooLarge {
            CoordinatedFileIO.quarantineCorruptFile(at: url)
            return nil
        }
    }

    public func loadBundle(for locationID: UUID) async throws -> LocationForecastBundle? {
        try await loadSnapshot(for: locationID)?.bundle
    }

    public func saveSnapshot(_ snapshot: CachedLocationSnapshot) async throws {
        try migrateLegacyIfNeeded()
        let url = fileURL(for: snapshot.locationID)

        var normalized = snapshot
        normalized.schemaVersion = SunsetHueConstants.currentCacheSchemaVersion
        let data = try encoder.encode(normalized)
        guard data.count <= SunsetHueConstants.maxCacheFileBytes else {
            throw SunsetHueError.storageTooLarge
        }

        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        let decoder = self.decoder
        coordinator.coordinate(
            writingItemAt: url,
            options: [.forReplacing],
            error: &coordinatorError
        ) { writeURL in
            do {
                if FileManager.default.fileExists(atPath: writeURL.path),
                   let existingData = try? Data(contentsOf: writeURL),
                   existingData.count <= SunsetHueConstants.maxCacheFileBytes,
                   let existing = try? decoder.decode(CachedLocationSnapshot.self, from: existingData),
                   normalized.fetchedAt < existing.fetchedAt,
                   normalized.status == .current,
                   existing.status == .current {
                    // Reject older successful fetches; allow status/metadata updates with same or newer attempt.
                    return
                }
                if FileManager.default.fileExists(atPath: writeURL.path),
                   let existingData = try? Data(contentsOf: writeURL),
                   let existing = try? decoder.decode(CachedLocationSnapshot.self, from: existingData),
                   normalized.lastAttemptAt < existing.lastAttemptAt {
                    return
                }
                let directory = writeURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
                try data.write(to: tempURL, options: .atomic)
                if FileManager.default.fileExists(atPath: writeURL.path) {
                    _ = try FileManager.default.replaceItemAt(writeURL, withItemAt: tempURL)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: writeURL)
                }
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    public func deleteLocation(_ locationID: UUID) async throws {
        try migrateLegacyIfNeeded()
        try CoordinatedFileIO.deleteItem(at: fileURL(for: locationID))
    }

    private func fileURL(for locationID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(locationID.uuidString).json")
    }

    private func migrateLegacyIfNeeded() throws {
        guard !didMigrateLegacy else { return }
        didMigrateLegacy = true
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else { return }
        guard let data = try? CoordinatedFileIO.readData(
            from: legacyFileURL,
            maxBytes: SunsetHueConstants.maxCacheFileBytes * 4
        ) else {
            CoordinatedFileIO.quarantineCorruptFile(at: legacyFileURL)
            return
        }
        guard let store = try? decoder.decode(CachedForecastStore.self, from: data) else {
            CoordinatedFileIO.quarantineCorruptFile(at: legacyFileURL)
            return
        }
        for (id, bundle) in store.bundles {
            let dest = fileURL(for: id)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            let snapshot = CachedLocationSnapshot.fromSuccessful(bundle: bundle)
            if let encoded = try? encoder.encode(snapshot) {
                try? CoordinatedFileIO.writeAtomically(encoded, to: dest)
            }
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = legacyFileURL.deletingLastPathComponent()
            .appendingPathComponent("\(legacyFileURL.lastPathComponent).migrated-\(stamp)")
        try? FileManager.default.moveItem(at: legacyFileURL, to: aside)
    }
}

public actor InMemorySettingsStore: SharedSettingsStore {
    private var state = SharedAppState()

    public init(state: SharedAppState = SharedAppState()) {
        self.state = state
    }

    public func load() async throws -> SharedAppState { state }

    public func save(_ state: SharedAppState) async throws {
        self.state = state
    }
}

public actor InMemoryForecastCache: ForecastCache {
    private var snapshots: [UUID: CachedLocationSnapshot] = [:]

    public init(snapshots: [UUID: CachedLocationSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    public func loadSnapshot(for locationID: UUID) async throws -> CachedLocationSnapshot? {
        snapshots[locationID]
    }

    public func loadBundle(for locationID: UUID) async throws -> LocationForecastBundle? {
        snapshots[locationID]?.bundle
    }

    public func saveSnapshot(_ snapshot: CachedLocationSnapshot) async throws {
        if let existing = snapshots[snapshot.locationID] {
            if snapshot.fetchedAt < existing.fetchedAt, snapshot.status == .current, existing.status == .current {
                return
            }
            if snapshot.lastAttemptAt < existing.lastAttemptAt {
                return
            }
        }
        snapshots[snapshot.locationID] = snapshot
    }

    public func deleteLocation(_ locationID: UUID) async throws {
        snapshots.removeValue(forKey: locationID)
    }
}

public enum SharedStorageFactory {
    public static func makeSettingsStore() -> any SharedSettingsStore {
        FileSettingsStore()
    }

    public static func makeForecastCache() -> any ForecastCache {
        FileForecastCache()
    }
}

extension JSONEncoder {
    static var sunsetHue: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var sunsetHue: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
