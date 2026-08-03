import Foundation
import CoreLocation
import SunsetHueCore

enum GeographicTimeZoneResolver {
    /// Reverse-geocodes a coordinate to a geographic IANA time zone, if available.
    static func timeZoneIdentifier(for location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                continuation.resume(returning: placemarks?.first?.timeZone?.identifier)
            }
        }
    }
}
