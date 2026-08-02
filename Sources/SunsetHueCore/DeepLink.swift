import Foundation

public enum DeepLink: Equatable, Sendable {
    case location(UUID)
    case openApp

    public static func locationURL(id: UUID) -> URL {
        URL(string: "\(SunsetHueConstants.urlScheme)://location/\(id.uuidString)")!
    }

    public static func openAppURL() -> URL {
        URL(string: "\(SunsetHueConstants.urlScheme)://")!
    }

    public static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == SunsetHueConstants.urlScheme else { return nil }
        let host = url.host?.lowercased()
        let pathParts = url.path.split(separator: "/").map(String.init)
        if host == "location", let idString = pathParts.first, let id = UUID(uuidString: idString) {
            return .location(id)
        }
        // Support sunsethue://location/<id> where "location" is the host.
        if host == "location", pathParts.isEmpty {
            return .openApp
        }
        // Support path-style sunsethue:///location/<id>
        if (host == nil || host?.isEmpty == true),
           pathParts.count >= 2,
           pathParts[0].lowercased() == "location",
           let id = UUID(uuidString: pathParts[1]) {
            return .location(id)
        }
        return .openApp
    }
}
