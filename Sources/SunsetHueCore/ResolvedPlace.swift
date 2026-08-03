import Foundation

/// Place chosen from MapKit search or equivalent resolver (no MapKit dependency).
public struct ResolvedPlace: Equatable, Sendable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String?

    public init(
        name: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String?
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// Mutable draft fields updated by place selection (testable without SwiftUI).
public struct LocationDraftPlaceFields: Equatable, Sendable {
    public var name: String
    public var latitude: String
    public var longitude: String
    public var timeZoneIdentifier: String

    public init(
        name: String,
        latitude: String,
        longitude: String,
        timeZoneIdentifier: String
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// Applies a resolved place. Time zone is updated only when non-nil.
    public mutating func apply(_ place: ResolvedPlace) {
        name = place.name
        latitude = String(format: "%.5f", place.latitude)
        longitude = String(format: "%.5f", place.longitude)
        if let timeZoneIdentifier = place.timeZoneIdentifier {
            self.timeZoneIdentifier = timeZoneIdentifier
        }
    }
}
