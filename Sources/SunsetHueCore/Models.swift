import Foundation

public struct Coordinates: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var normalized: Coordinates {
        Coordinates(
            latitude: Coordinates.normalize(latitude),
            longitude: Coordinates.normalize(longitude)
        )
    }

    public static func normalize(_ value: Double) -> Double {
        let places = SunsetHueConstants.coordinateDecimalPlaces
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }

    public static func validateLatitude(_ value: Double) throws {
        guard (-90...90).contains(value), value.isFinite else {
            throw SunsetHueError.invalidCoordinates
        }
    }

    public static func validateLongitude(_ value: Double) throws {
        guard (-180...180).contains(value), value.isFinite else {
            throw SunsetHueError.invalidCoordinates
        }
    }

    public func validated() throws -> Coordinates {
        try Self.validateLatitude(latitude)
        try Self.validateLongitude(longitude)
        return normalized
    }
}

public struct MagicHourWindow: Codable, Hashable, Sendable {
    public let start: Date?
    public let end: Date?

    public init(start: Date?, end: Date?) {
        self.start = start
        self.end = end
    }
}

public struct EventForecast: Codable, Hashable, Sendable {
    public let responseTime: Date
    public let location: Coordinates
    public let gridLocation: Coordinates
    public let eventType: EventType
    public let modelData: Bool
    public let quality: Double?
    public let qualityText: String?
    public let cloudCover: Double?
    public let eventTime: Date?
    public let direction: Double?
    public let blueHour: MagicHourWindow?
    public let goldenHour: MagicHourWindow?
    public let forecastDate: Date?

    public init(
        responseTime: Date,
        location: Coordinates,
        gridLocation: Coordinates,
        eventType: EventType,
        modelData: Bool,
        quality: Double?,
        qualityText: String?,
        cloudCover: Double?,
        eventTime: Date?,
        direction: Double?,
        blueHour: MagicHourWindow?,
        goldenHour: MagicHourWindow?,
        forecastDate: Date? = nil
    ) {
        self.responseTime = responseTime
        self.location = location
        self.gridLocation = gridLocation
        self.eventType = eventType
        self.modelData = modelData
        self.quality = quality
        self.qualityText = qualityText
        self.cloudCover = cloudCover
        self.eventTime = eventTime
        self.direction = direction
        self.blueHour = blueHour
        self.goldenHour = goldenHour
        self.forecastDate = forecastDate
    }

    public var isQualityAvailable: Bool {
        modelData && quality != nil
    }

    public func withForecastDate(_ date: Date) -> EventForecast {
        EventForecast(
            responseTime: responseTime,
            location: location,
            gridLocation: gridLocation,
            eventType: eventType,
            modelData: modelData,
            quality: quality,
            qualityText: qualityText,
            cloudCover: cloudCover,
            eventTime: eventTime,
            direction: direction,
            blueHour: blueHour,
            goldenHour: goldenHour,
            forecastDate: date
        )
    }
}

public struct ForecastKey: Codable, Hashable, Sendable {
    public let dayOffset: Int
    public let eventType: EventType

    public init(dayOffset: Int, eventType: EventType) {
        self.dayOffset = dayOffset
        self.eventType = eventType
    }
}

public struct SavedLocation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZoneIdentifier: String
    public var forecastDays: Int
    public var includeSunrise: Bool
    public var includeSunset: Bool
    public var refreshIntervalHours: Int

    public init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        forecastDays: Int = SunsetHueConstants.defaultForecastDays,
        includeSunrise: Bool = true,
        includeSunset: Bool = true,
        refreshIntervalHours: Int = SunsetHueConstants.defaultRefreshIntervalHours
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.forecastDays = forecastDays
        self.includeSunrise = includeSunrise
        self.includeSunset = includeSunset
        self.refreshIntervalHours = refreshIntervalHours
    }

    public var coordinates: Coordinates {
        Coordinates(latitude: latitude, longitude: longitude)
    }

    public var timeZone: TimeZone? {
        TimeZone(identifier: timeZoneIdentifier)
    }

    public var enabledEvents: [EventType] {
        var events: [EventType] = []
        if includeSunrise { events.append(.sunrise) }
        if includeSunset { events.append(.sunset) }
        return events
    }

    public var normalizedCoordinateKey: String {
        let normalized = coordinates.normalized
        return String(
            format: "%.\(SunsetHueConstants.coordinateDecimalPlaces)f,%.\(SunsetHueConstants.coordinateDecimalPlaces)f",
            normalized.latitude,
            normalized.longitude
        )
    }

    public func validated(againstExisting existing: [SavedLocation] = []) throws -> SavedLocation {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw SunsetHueError.invalidLocation("Display name must not be empty.")
        }
        let coords = try coordinates.validated()
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw SunsetHueError.invalidLocation("Time zone identifier is invalid.")
        }
        guard (1...SunsetHueConstants.maxForecastDays).contains(forecastDays) else {
            throw SunsetHueError.invalidLocation("Forecast days must be between 1 and 3.")
        }
        guard includeSunrise || includeSunset else {
            throw SunsetHueError.invalidLocation("Enable at least sunrise or sunset.")
        }
        guard SunsetHueConstants.validRefreshIntervalHours.contains(refreshIntervalHours) else {
            throw SunsetHueError.invalidLocation("Refresh interval must be 6, 12, or 24 hours.")
        }
        let candidate = SavedLocation(
            id: id,
            name: trimmedName,
            latitude: coords.latitude,
            longitude: coords.longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            forecastDays: forecastDays,
            includeSunrise: includeSunrise,
            includeSunset: includeSunset,
            refreshIntervalHours: refreshIntervalHours
        )
        let duplicate = existing.contains {
            $0.id != candidate.id && $0.normalizedCoordinateKey == candidate.normalizedCoordinateKey
        }
        if duplicate {
            throw SunsetHueError.duplicateLocation
        }
        return candidate
    }
}

public struct LocationForecastBundle: Codable, Hashable, Sendable {
    public let locationID: UUID
    public let fetchedAt: Date
    public let forecasts: [EventForecast]

    public init(locationID: UUID, fetchedAt: Date, forecasts: [EventForecast]) {
        self.locationID = locationID
        self.fetchedAt = fetchedAt
        self.forecasts = forecasts
    }

    public init(locationID: UUID, fetchedAt: Date, keyedForecasts: [ForecastKey: EventForecast]) {
        self.locationID = locationID
        self.fetchedAt = fetchedAt
        self.forecasts = keyedForecasts.keys.sorted { lhs, rhs in
            if lhs.dayOffset != rhs.dayOffset { return lhs.dayOffset < rhs.dayOffset }
            return lhs.eventType.rawValue < rhs.eventType.rawValue
        }.compactMap { keyedForecasts[$0] }
    }

    public func forecast(dayOffset: Int, eventType: EventType, timeZone: TimeZone, now: Date = Date()) -> EventForecast? {
        let calculator = ForecastDateCalculator()
        return forecasts.first { forecast in
            guard forecast.eventType == eventType else { return false }
            let refDate = forecast.forecastDate ?? forecast.eventTime
            guard let refDate else { return false }
            return calculator.dayOffset(for: refDate, timeZone: timeZone, now: now) == dayOffset
        }
    }

    public func forecasts(forDayOffset dayOffset: Int, timeZone: TimeZone, now: Date = Date()) -> [EventForecast] {
        EventType.allCases.compactMap { forecast(dayOffset: dayOffset, eventType: $0, timeZone: timeZone, now: now) }
    }

    /// Whether this bundle contains forecast coverage into at least the next local calendar day
    /// (day offset 1) for each enabled event.
    public func hasOperationalCoverage(
        for location: SavedLocation,
        now: Date = Date()
    ) -> Bool {
        guard let timeZone = location.timeZone, !location.enabledEvents.isEmpty else {
            return true
        }
        for event in location.enabledEvents {
            if forecast(dayOffset: 1, eventType: event, timeZone: timeZone, now: now) == nil {
                return false
            }
        }
        return true
    }
}

public struct RefreshOutcome: Sendable {
    public let bundle: LocationForecastBundle?
    public let error: SunsetHueError?
    public let usedCache: Bool

    public init(bundle: LocationForecastBundle?, error: SunsetHueError?, usedCache: Bool) {
        self.bundle = bundle
        self.error = error
        self.usedCache = usedCache
    }
}

public struct SharedAppState: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var locations: [SavedLocation]
    public var selectedLocationID: UUID?

    public enum CodingKeys: String, CodingKey {
        case schemaVersion
        case locations
        case selectedLocationID
        // Legacy fields ignored on decode / omitted on encode.
        case lastErrorMessage
        case lastErrorIsAuthentication
        case lastSuccessfulUpdate
    }

    public init(
        schemaVersion: Int = SunsetHueConstants.currentSettingsSchemaVersion,
        locations: [SavedLocation] = [],
        selectedLocationID: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.locations = locations
        self.selectedLocationID = selectedLocationID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? SunsetHueConstants.currentSettingsSchemaVersion
        locations = try container.decodeIfPresent([SavedLocation].self, forKey: .locations) ?? []
        selectedLocationID = try container.decodeIfPresent(UUID.self, forKey: .selectedLocationID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(locations, forKey: .locations)
        try container.encodeIfPresent(selectedLocationID, forKey: .selectedLocationID)
    }

    public var selectedLocation: SavedLocation? {
        guard let selectedLocationID else { return locations.first }
        return locations.first(where: { $0.id == selectedLocationID }) ?? locations.first
    }

    public mutating func moveLocations(fromOffsets: IndexSet, toOffset: Int) {
        var items = locations
        let movingElements = fromOffsets.map { items[$0] }
        for index in fromOffsets.sorted(by: >) {
            items.remove(at: index)
        }
        let insertIndex = min(toOffset - fromOffsets.filter { $0 < toOffset }.count, items.count)
        items.insert(contentsOf: movingElements, at: max(0, insertIndex))
        locations = items
    }
}

/// Widget-safe per-location forecast snapshot (no secrets).
public enum RefreshStatus: Codable, Hashable, Sendable {
    case current
    case stale
    case authenticationRequired
    case rateLimited(retryAfter: Date?)
    case temporarilyUnavailable
    /// Invalid coordinates/location/request — no automatic retry until configuration changes.
    case invalidRequest
    /// Malformed or incompatible server response — long backoff.
    case invalidResponse
}

public struct CachedLocationSnapshot: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public let locationID: UUID
    public var fetchedAt: Date
    public var lastAttemptAt: Date
    public var forecasts: [EventForecast]
    public var status: RefreshStatus
    /// Earliest time an automatic retry should run. Nil means status-specific default rules apply.
    public var nextAttemptAt: Date?
    public var consecutiveFailureCount: Int

    public enum CodingKeys: String, CodingKey {
        case schemaVersion
        case locationID
        case fetchedAt
        case lastAttemptAt
        case forecasts
        case status
        case nextAttemptAt
        case consecutiveFailureCount
        // Legacy LocationCacheDocument fields (decode-only migration).
        case lastErrorMessage
        case lastErrorIsAuthentication
        case bundle
    }

    public init(
        schemaVersion: Int = SunsetHueConstants.currentCacheSchemaVersion,
        locationID: UUID,
        fetchedAt: Date,
        lastAttemptAt: Date,
        forecasts: [EventForecast],
        status: RefreshStatus,
        nextAttemptAt: Date? = nil,
        consecutiveFailureCount: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.locationID = locationID
        self.fetchedAt = fetchedAt
        self.lastAttemptAt = lastAttemptAt
        self.forecasts = forecasts
        self.status = status
        self.nextAttemptAt = nextAttemptAt
        self.consecutiveFailureCount = consecutiveFailureCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let status = try container.decodeIfPresent(RefreshStatus.self, forKey: .status),
           container.contains(.forecasts) {
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? SunsetHueConstants.currentCacheSchemaVersion
            locationID = try container.decode(UUID.self, forKey: .locationID)
            fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
            lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt) ?? fetchedAt
            forecasts = try container.decode([EventForecast].self, forKey: .forecasts)
            self.status = status
            nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
            consecutiveFailureCount = try container.decodeIfPresent(Int.self, forKey: .consecutiveFailureCount) ?? 0
            return
        }

        // Migrate legacy LocationCacheDocument.
        let bundle = try container.decodeIfPresent(LocationForecastBundle.self, forKey: .bundle)
        locationID = bundle?.locationID ?? UUID()
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? Date.distantPast
        lastAttemptAt = fetchedAt
        forecasts = bundle?.forecasts ?? []
        schemaVersion = SunsetHueConstants.currentCacheSchemaVersion
        nextAttemptAt = nil
        consecutiveFailureCount = 0
        let auth = try container.decodeIfPresent(Bool.self, forKey: .lastErrorIsAuthentication) ?? false
        let hasError = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage) != nil
        if auth {
            status = .authenticationRequired
        } else if hasError {
            status = .temporarilyUnavailable
        } else if forecasts.isEmpty {
            status = .temporarilyUnavailable
        } else {
            status = .current
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(locationID, forKey: .locationID)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encode(lastAttemptAt, forKey: .lastAttemptAt)
        try container.encode(forecasts, forKey: .forecasts)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(nextAttemptAt, forKey: .nextAttemptAt)
        try container.encode(consecutiveFailureCount, forKey: .consecutiveFailureCount)
    }

    public var bundle: LocationForecastBundle? {
        guard !forecasts.isEmpty else { return nil }
        return LocationForecastBundle(locationID: locationID, fetchedAt: fetchedAt, forecasts: forecasts)
    }

    public func isFresh(refreshIntervalHours: Int, now: Date = Date()) -> Bool {
        let hours = SunsetHueConstants.validRefreshIntervalHours.contains(refreshIntervalHours)
            ? refreshIntervalHours
            : SunsetHueConstants.defaultRefreshIntervalHours
        return now.timeIntervalSince(fetchedAt) < TimeInterval(hours * 3600)
            && status == .current
    }

    /// Determines whether this snapshot has sufficient future forecast coverage
    /// into at least the next local calendar day (day offset 1) for the location's enabled events.
    public func hasOperationalCoverage(
        for location: SavedLocation,
        now: Date = Date()
    ) -> Bool {
        guard let bundle else { return false }
        return bundle.hasOperationalCoverage(for: location, now: now)
    }

    public static func fromSuccessful(bundle: LocationForecastBundle, attemptedAt: Date = Date()) -> CachedLocationSnapshot {
        CachedLocationSnapshot(
            locationID: bundle.locationID,
            fetchedAt: bundle.fetchedAt,
            lastAttemptAt: attemptedAt,
            forecasts: bundle.forecasts,
            status: .current,
            nextAttemptAt: nil,
            consecutiveFailureCount: 0
        )
    }

    /// Next automatic refresh time for this snapshot, or nil when no automatic retry should be scheduled.
    public func nextScheduledRefresh(
        refreshIntervalHours: Int,
        timeZone: TimeZone? = nil,
        now: Date = Date()
    ) -> Date? {
        switch status {
        case .authenticationRequired, .invalidRequest:
            return nil
        case .rateLimited(let retryAfter):
            let base = retryAfter ?? nextAttemptAt ?? now
            let jitter = TimeInterval(SunsetHueConstants.rateLimitJitterSeconds(for: locationID))
            return max(now, base.addingTimeInterval(jitter))
        case .current:
            let hours = SunsetHueConstants.validRefreshIntervalHours.contains(refreshIntervalHours)
                ? refreshIntervalHours
                : SunsetHueConstants.defaultRefreshIntervalHours
            let intervalDate = fetchedAt.addingTimeInterval(TimeInterval(hours * 3600))
            if let timeZone {
                let midnight = ForecastDateCalculator().nextMidnightRefresh(timeZone: timeZone, now: now)
                return min(intervalDate, midnight)
            }
            return intervalDate
        case .stale:
            return nextAttemptAt ?? now
        case .temporarilyUnavailable, .invalidResponse:
            return nextAttemptAt ?? now
        }
    }
}

/// Computes persisted backoff deadlines for failed refreshes.
public enum RefreshBackoff {
    public static func nextAttempt(
        status: RefreshStatus,
        previousFailureCount: Int,
        locationID: UUID,
        from attemptedAt: Date,
        rateLimitRetryAfter: Date? = nil
    ) -> (nextAttemptAt: Date?, consecutiveFailureCount: Int) {
        switch status {
        case .current, .stale:
            return (nil, 0)
        case .authenticationRequired, .invalidRequest:
            return (nil, previousFailureCount)
        case .rateLimited:
            let jitter = TimeInterval(SunsetHueConstants.rateLimitJitterSeconds(for: locationID))
            let base = rateLimitRetryAfter ?? attemptedAt.addingTimeInterval(15 * 60)
            return (base.addingTimeInterval(jitter), previousFailureCount + 1)
        case .temporarilyUnavailable:
            let count = previousFailureCount + 1
            let ladder = SunsetHueConstants.temporaryUnavailableBackoffSeconds
            let index = min(max(count - 1, 0), ladder.count - 1)
            let delay = min(ladder[index], SunsetHueConstants.maxRefreshBackoffSeconds)
            return (attemptedAt.addingTimeInterval(delay), count)
        case .invalidResponse:
            let count = previousFailureCount + 1
            let base = SunsetHueConstants.invalidResponseInitialBackoffSeconds
            let delay = min(base * pow(2.0, Double(max(0, count - 1))), SunsetHueConstants.maxRefreshBackoffSeconds)
            return (attemptedAt.addingTimeInterval(delay), count)
        }
    }
}

/// Legacy monolithic cache shape (migration only).
public struct CachedForecastStore: Codable, Hashable, Sendable {
    public var bundles: [UUID: LocationForecastBundle]

    public init(bundles: [UUID: LocationForecastBundle] = [:]) {
        self.bundles = bundles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let dict = try? container.decode([String: LocationForecastBundle].self, forKey: .bundles) {
            var mapped: [UUID: LocationForecastBundle] = [:]
            for (key, value) in dict {
                if let id = UUID(uuidString: key) {
                    mapped[id] = value
                }
            }
            bundles = mapped
        } else {
            bundles = try container.decodeIfPresent([UUID: LocationForecastBundle].self, forKey: .bundles) ?? [:]
        }
    }

    private enum CodingKeys: String, CodingKey {
        case bundles
    }
}
