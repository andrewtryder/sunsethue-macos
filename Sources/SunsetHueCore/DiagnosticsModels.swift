import Foundation

/// Trigger reason for a forecast refresh operation.
public enum RefreshTrigger: String, Codable, Hashable, Sendable, CaseIterable {
    case bootstrap
    case manual
    case scheduled
    case backgroundActivity
    case didWake
    case didBecomeActive
    case apiKeyChanged

    public var displayName: String {
        switch self {
        case .bootstrap: return "Bootstrap"
        case .manual: return "Manual"
        case .scheduled: return "Scheduled"
        case .backgroundActivity: return "Background Activity"
        case .didWake: return "Wake"
        case .didBecomeActive: return "Active"
        case .apiKeyChanged: return "API Key Changed"
        }
    }
}

/// Normalized result classification for a forecast refresh attempt.
public enum RefreshResultSummary: String, Codable, Hashable, Sendable, CaseIterable {
    case skippedFresh
    case refreshedSuccessfully
    case authenticationRequired
    case rateLimited
    case transientFailure
    case invalidRequest
    case persistenceFailure

    public var displayName: String {
        switch self {
        case .skippedFresh: return "Skipped (Fresh)"
        case .refreshedSuccessfully: return "Refreshed Successfully"
        case .authenticationRequired: return "Authentication Required"
        case .rateLimited: return "Rate Limited"
        case .transientFailure: return "Transient Failure"
        case .invalidRequest: return "Invalid Request"
        case .persistenceFailure: return "Persistence Failure"
        }
    }
}

/// A single bounded diagnostics entry for a refresh attempt or decision.
public struct RefreshActivityRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let locationID: UUID?
    public let locationName: String
    public let trigger: RefreshTrigger
    public let result: RefreshResultSummary
    public let details: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        locationID: UUID?,
        locationName: String,
        trigger: RefreshTrigger,
        result: RefreshResultSummary,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.locationID = locationID
        self.locationName = locationName
        self.trigger = trigger
        self.result = result
        self.details = details
    }
}

/// Thread-safe bounded in-memory rolling history of refresh activity.
public actor RefreshActivityRecorder: Sendable {
    public static let defaultMaxEntries = 50

    private let maxEntries: Int
    private var entries: [RefreshActivityRecord] = []

    public init(maxEntries: Int = RefreshActivityRecorder.defaultMaxEntries) {
        self.maxEntries = max(1, maxEntries)
    }

    public func record(
        locationID: UUID?,
        locationName: String,
        trigger: RefreshTrigger,
        result: RefreshResultSummary,
        details: String? = nil,
        timestamp: Date = Date()
    ) {
        let record = RefreshActivityRecord(
            timestamp: timestamp,
            locationID: locationID,
            locationName: locationName,
            trigger: trigger,
            result: result,
            details: details
        )
        entries.insert(record, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    /// Returns recent activities ordered from newest to oldest.
    public func recentEntries() -> [RefreshActivityRecord] {
        entries
    }

    public func clear() {
        entries.removeAll()
    }
}

/// Computes human-readable forecast coverage strings.
public enum CoverageDiagnostics: Sendable {
    public static func coverageDescription(
        for location: SavedLocation,
        snapshot: CachedLocationSnapshot?,
        now: Date = Date()
    ) -> String {
        guard let snapshot, !snapshot.forecasts.isEmpty else {
            return "No forecast cached"
        }
        guard let timeZone = location.timeZone else {
            return "Unknown time zone"
        }
        let calc = ForecastDateCalculator()
        let daysWithForecasts = Set(snapshot.forecasts.compactMap { forecast -> Int? in
            guard let refDate = forecast.forecastDate ?? forecast.eventTime else { return nil }
            return calc.dayOffset(for: refDate, timeZone: timeZone, now: now)
        })
        if daysWithForecasts.contains(0) && daysWithForecasts.contains(1) {
            if daysWithForecasts.contains(2) {
                return "Today + Tomorrow + 2d"
            }
            return "Today + Tomorrow"
        } else if daysWithForecasts.contains(0) {
            return "Today only"
        } else if daysWithForecasts.contains(1) {
            return "Tomorrow only"
        } else if daysWithForecasts.isEmpty {
            return "No valid dates"
        } else {
            return "Partial (\(daysWithForecasts.count) days)"
        }
    }
}

/// Snapshot of diagnostics for a specific configured location.
public struct LocationRefreshDiagnostics: Identifiable, Sendable {
    public let id: UUID
    public let locationName: String
    public let status: RefreshStatus
    public let statusDisplayName: String
    public let lastSuccess: Date?
    public let lastAttempt: Date?
    public let nextScheduledRefresh: Date?
    public let refreshIntervalHours: Int
    public let coverageDescription: String
    public let isRefreshing: Bool

    public init(
        id: UUID,
        locationName: String,
        status: RefreshStatus,
        statusDisplayName: String,
        lastSuccess: Date?,
        lastAttempt: Date?,
        nextScheduledRefresh: Date?,
        refreshIntervalHours: Int,
        coverageDescription: String,
        isRefreshing: Bool = false
    ) {
        self.id = id
        self.locationName = locationName
        self.status = status
        self.statusDisplayName = statusDisplayName
        self.lastSuccess = lastSuccess
        self.lastAttempt = lastAttempt
        self.nextScheduledRefresh = nextScheduledRefresh
        self.refreshIntervalHours = refreshIntervalHours
        self.coverageDescription = coverageDescription
        self.isRefreshing = isRefreshing
    }

    public static func make(
        location: SavedLocation,
        snapshot: CachedLocationSnapshot?,
        isRefreshing: Bool = false,
        now: Date = Date()
    ) -> LocationRefreshDiagnostics {
        let statusName: String
        if let status = snapshot?.status {
            switch status {
            case .current: statusName = "Current"
            case .stale: statusName = "Stale"
            case .authenticationRequired: statusName = "Authentication Required"
            case .rateLimited(let retryAfter):
                if let retryAfter {
                    let formatted = retryAfter.formatted(date: .omitted, time: .shortened)
                    statusName = "Rate Limited (until \(formatted))"
                } else {
                    statusName = "Rate Limited"
                }
            case .temporarilyUnavailable: statusName = "Temporarily Unavailable"
            case .invalidRequest: statusName = "Invalid Request"
            case .invalidResponse: statusName = "Invalid Server Response"
            }
        } else {
            statusName = "Not Cached"
        }

        let nextRefresh = snapshot?.nextScheduledRefresh(
            refreshIntervalHours: location.refreshIntervalHours,
            timeZone: location.timeZone,
            now: now
        )

        let coverage = CoverageDiagnostics.coverageDescription(for: location, snapshot: snapshot, now: now)

        return LocationRefreshDiagnostics(
            id: location.id,
            locationName: location.name,
            status: snapshot?.status ?? .stale,
            statusDisplayName: statusName,
            lastSuccess: snapshot?.fetchedAt,
            lastAttempt: snapshot?.lastAttemptAt,
            nextScheduledRefresh: nextRefresh,
            refreshIntervalHours: location.refreshIntervalHours,
            coverageDescription: coverage,
            isRefreshing: isRefreshing
        )
    }
}

/// Snapshot of background refresh subsystem state.
public struct BackgroundRefreshDiagnostics: Sendable {
    public let isActive: Bool
    public let schedulerName: String
    public let intervalDescription: String
    public let lastActivityAt: Date?
    public let lastDisposition: String?
    public let isLaunchAtLoginEnabled: Bool

    public init(
        isActive: Bool = true,
        schedulerName: String = "NSBackgroundActivityScheduler",
        intervalDescription: String = "~30 min",
        lastActivityAt: Date? = nil,
        lastDisposition: String? = nil,
        isLaunchAtLoginEnabled: Bool = false
    ) {
        self.isActive = isActive
        self.schedulerName = schedulerName
        self.intervalDescription = intervalDescription
        self.lastActivityAt = lastActivityAt
        self.lastDisposition = lastDisposition
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
    }
}

/// Snapshot of shared storage and widget coordination state.
public struct StorageDiagnostics: Sendable {
    public let storageMode: StorageMode
    public let storageModeDisplayName: String
    public let appGroupIdentifier: String?
    public let isAppGroupAvailable: Bool
    public let isSettingsReadable: Bool
    public let isForecastCacheReadable: Bool
    public let lastCacheCommit: Date?
    public let lastWidgetReloadRequested: Date?

    public init(
        storageMode: StorageMode,
        storageModeDisplayName: String,
        appGroupIdentifier: String?,
        isAppGroupAvailable: Bool,
        isSettingsReadable: Bool,
        isForecastCacheReadable: Bool,
        lastCacheCommit: Date? = nil,
        lastWidgetReloadRequested: Date? = nil
    ) {
        self.storageMode = storageMode
        self.storageModeDisplayName = storageModeDisplayName
        self.appGroupIdentifier = appGroupIdentifier
        self.isAppGroupAvailable = isAppGroupAvailable
        self.isSettingsReadable = isSettingsReadable
        self.isForecastCacheReadable = isForecastCacheReadable
        self.lastCacheCommit = lastCacheCommit
        self.lastWidgetReloadRequested = lastWidgetReloadRequested
    }
}

/// Global thread-safe recorder for WidgetCenter reload requests and cache commit events.
public final class WidgetReloadStateTracker: @unchecked Sendable {
    public static let shared = WidgetReloadStateTracker()

    private let lock = NSLock()
    private var _lastReloadRequested: Date?
    private var _lastCacheCommit: Date?

    public init() {}

    public var lastReloadRequested: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _lastReloadRequested
    }

    public var lastCacheCommit: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _lastCacheCommit
    }

    public func recordReloadRequest(at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        _lastReloadRequested = date
    }

    public func recordCacheCommit(at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        _lastCacheCommit = date
    }
}
