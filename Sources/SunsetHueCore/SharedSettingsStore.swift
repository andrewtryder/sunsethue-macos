import Foundation

public protocol SharedSettingsStore: Sendable {
    func load() throws -> SharedAppState
    func save(_ state: SharedAppState) throws
}

public protocol ForecastCache: Sendable {
    func load() throws -> CachedForecastStore
    func save(_ store: CachedForecastStore) throws
    func loadBundle(for locationID: UUID) throws -> LocationForecastBundle?
    func saveBundle(_ bundle: LocationForecastBundle) throws
}

/// Prefers App Group-backed files when the sandbox container exists (signed widget builds).
public enum SharedStorageFactory {
    public static func makeSettingsStore() -> SharedSettingsStore {
        FileSettingsStore()
    }

    public static func makeForecastCache() -> ForecastCache {
        FileForecastCache()
    }
}

public final class FileSettingsStore: SharedSettingsStore, @unchecked Sendable {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public init(fileURL: URL = AppSupportPaths.appStateURL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.sortedKeys]
    }

    public func load() throws -> SharedAppState {
        lock.lock(); defer { lock.unlock() }
        try prepareStoreDirectory()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return SharedAppState()
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(SharedAppState.self, from: data)
    }

    public func save(_ state: SharedAppState) throws {
        lock.lock(); defer { lock.unlock() }
        try prepareStoreDirectory()
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    private func prepareStoreDirectory() throws {
        if fileURL.standardizedFileURL == AppSupportPaths.appStateURL.standardizedFileURL {
            try AppSupportPaths.migrateLegacySharedFilesIfNeeded()
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

public final class FileForecastCache: ForecastCache, @unchecked Sendable {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public init(fileURL: URL = AppSupportPaths.forecastCacheURL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.sortedKeys]
    }

    public func load() throws -> CachedForecastStore {
        lock.lock(); defer { lock.unlock() }
        try prepareStoreDirectory()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return CachedForecastStore()
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(CachedForecastStore.self, from: data)
    }

    public func save(_ store: CachedForecastStore) throws {
        lock.lock(); defer { lock.unlock() }
        try prepareStoreDirectory()
        let data = try encoder.encode(store)
        try data.write(to: fileURL, options: .atomic)
    }

    private func prepareStoreDirectory() throws {
        if fileURL.standardizedFileURL == AppSupportPaths.forecastCacheURL.standardizedFileURL {
            try AppSupportPaths.migrateLegacySharedFilesIfNeeded()
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    public func loadBundle(for locationID: UUID) throws -> LocationForecastBundle? {
        try load().bundles[locationID]
    }

    public func saveBundle(_ bundle: LocationForecastBundle) throws {
        var store = try load()
        store.bundles[bundle.locationID] = bundle
        try save(store)
    }
}

public final class AppGroupSettingsStore: SharedSettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(appGroupIdentifier: String = SunsetHueConstants.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() throws -> SharedAppState {
        guard let data = defaults.data(forKey: "sharedAppState") else {
            return SharedAppState()
        }
        return try decoder.decode(SharedAppState.self, from: data)
    }

    public func save(_ state: SharedAppState) throws {
        let data = try encoder.encode(state)
        defaults.set(data, forKey: "sharedAppState")
    }
}

public final class AppGroupForecastCache: ForecastCache, @unchecked Sendable {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(appGroupIdentifier: String = SunsetHueConstants.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() throws -> CachedForecastStore {
        guard let data = defaults.data(forKey: "forecastCache") else {
            return CachedForecastStore()
        }
        return try decoder.decode(CachedForecastStore.self, from: data)
    }

    public func save(_ store: CachedForecastStore) throws {
        let data = try encoder.encode(store)
        defaults.set(data, forKey: "forecastCache")
    }

    public func loadBundle(for locationID: UUID) throws -> LocationForecastBundle? {
        try load().bundles[locationID]
    }

    public func saveBundle(_ bundle: LocationForecastBundle) throws {
        var store = try load()
        store.bundles[bundle.locationID] = bundle
        try save(store)
    }
}

public final class InMemorySettingsStore: SharedSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: SharedAppState

    public init(state: SharedAppState = SharedAppState()) {
        self.state = state
    }

    public func load() throws -> SharedAppState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    public func save(_ state: SharedAppState) throws {
        lock.lock(); defer { lock.unlock() }
        self.state = state
    }
}

public final class InMemoryForecastCache: ForecastCache, @unchecked Sendable {
    private let lock = NSLock()
    private var store: CachedForecastStore

    public init(store: CachedForecastStore = CachedForecastStore()) {
        self.store = store
    }

    public func load() throws -> CachedForecastStore {
        lock.lock(); defer { lock.unlock() }
        return store
    }

    public func save(_ store: CachedForecastStore) throws {
        lock.lock(); defer { lock.unlock() }
        self.store = store
    }

    public func loadBundle(for locationID: UUID) throws -> LocationForecastBundle? {
        try load().bundles[locationID]
    }

    public func saveBundle(_ bundle: LocationForecastBundle) throws {
        var current = try load()
        current.bundles[bundle.locationID] = bundle
        try save(current)
    }
}
