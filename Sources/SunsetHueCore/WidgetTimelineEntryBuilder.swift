import Foundation

/// Pure description of a widget timeline entry (no WidgetKit dependency).
public struct WidgetTimelineEntryModel: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case placeholder
        case onboarding
        case forecast
        case cached
        case stale
        case authentication
        case unavailable
    }

    public let kind: Kind
    public let location: SavedLocation?
    public let bundle: LocationForecastBundle?
    public let statusMessage: String?

    public init(
        kind: Kind,
        location: SavedLocation?,
        bundle: LocationForecastBundle?,
        statusMessage: String?
    ) {
        self.kind = kind
        self.location = location
        self.bundle = bundle
        self.statusMessage = statusMessage
    }
}

/// Builds production widget timeline content. Preview fixtures must never appear here.
public enum WidgetTimelineEntryBuilder {
    public static let missingCacheMessage = "Open SunsetHue to fetch a forecast"

    /// Production entry for a resolved location and optional cache snapshot.
    public static func makeEntry(
        location: SavedLocation,
        snapshot: CachedLocationSnapshot?,
        now: Date = Date()
    ) -> WidgetTimelineEntryModel {
        guard let snapshot else {
            return WidgetTimelineEntryModel(
                kind: .unavailable,
                location: location,
                bundle: nil,
                statusMessage: missingCacheMessage
            )
        }

        let bundle = snapshot.bundle

        switch snapshot.status {
        case .authenticationRequired:
            return WidgetTimelineEntryModel(
                kind: .authentication,
                location: location,
                bundle: bundle,
                statusMessage: "Open SunsetHue to update the API key"
            )
        case .current where snapshot.isFresh(refreshIntervalHours: location.refreshIntervalHours, now: now):
            return WidgetTimelineEntryModel(
                kind: .forecast,
                location: location,
                bundle: bundle,
                statusMessage: nil
            )
        case .current, .stale, .rateLimited, .temporarilyUnavailable, .invalidRequest, .invalidResponse:
            let message: String
            if bundle == nil {
                switch snapshot.status {
                case .temporarilyUnavailable:
                    message = "Forecast unavailable"
                case .invalidRequest:
                    message = "Coordinates were rejected. Check latitude and longitude."
                case .invalidResponse:
                    message = "SunsetHue returned an incompatible response."
                default:
                    message = missingCacheMessage
                }
            } else {
                message = "Updated \(compactRelative(from: snapshot.fetchedAt, now: now))"
            }
            return WidgetTimelineEntryModel(
                kind: bundle == nil ? .unavailable : .stale,
                location: location,
                bundle: bundle,
                statusMessage: message
            )
        }
    }

    public static func makeOnboarding(message: String) -> WidgetTimelineEntryModel {
        WidgetTimelineEntryModel(
            kind: .onboarding,
            location: nil,
            bundle: nil,
            statusMessage: message
        )
    }

    private static func compactRelative(from date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}
