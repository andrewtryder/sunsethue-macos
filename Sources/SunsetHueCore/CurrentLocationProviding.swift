import Foundation

public protocol CurrentLocationProviding: AnyObject {
    func requestLocation() async throws -> CurrentLocationResult
}

public struct CurrentLocationResult: Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String

    public init(latitude: Double, longitude: Double, timeZoneIdentifier: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// Test double that counts invocations.
public final class CountingLocationProvider: CurrentLocationProviding, @unchecked Sendable {
    public private(set) var requestCount = 0

    public init() {}

    public func requestLocation() async throws -> CurrentLocationResult {
        requestCount += 1
        return CurrentLocationResult(latitude: 40.0, longitude: -74.0, timeZoneIdentifier: "America/New_York")
    }
}
