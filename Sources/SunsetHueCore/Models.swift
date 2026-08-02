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
            guard forecast.eventType == eventType, let forecastDate = forecast.forecastDate else { return false }
            return calculator.dayOffset(for: forecastDate, timeZone: timeZone, now: now) == dayOffset
        }
    }

    public func forecasts(forDayOffset dayOffset: Int, timeZone: TimeZone, now: Date = Date()) -> [EventForecast] {
        EventType.allCases.compactMap { forecast(dayOffset: dayOffset, eventType: $0, timeZone: timeZone, now: now) }
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
    public var locations: [SavedLocation]
    public var selectedLocationID: UUID?
    public var lastErrorMessage: String?
    public var lastErrorIsAuthentication: Bool
    public var lastSuccessfulUpdate: Date?

    public init(
        locations: [SavedLocation] = [],
        selectedLocationID: UUID? = nil,
        lastErrorMessage: String? = nil,
        lastErrorIsAuthentication: Bool = false,
        lastSuccessfulUpdate: Date? = nil
    ) {
        self.locations = locations
        self.selectedLocationID = selectedLocationID
        self.lastErrorMessage = lastErrorMessage
        self.lastErrorIsAuthentication = lastErrorIsAuthentication
        self.lastSuccessfulUpdate = lastSuccessfulUpdate
    }

    public var selectedLocation: SavedLocation? {
        guard let selectedLocationID else { return locations.first }
        return locations.first(where: { $0.id == selectedLocationID }) ?? locations.first
    }
}

public struct CachedForecastStore: Codable, Hashable, Sendable {
    public var bundles: [UUID: LocationForecastBundle]

    public init(bundles: [UUID: LocationForecastBundle] = [:]) {
        self.bundles = bundles
    }
}
