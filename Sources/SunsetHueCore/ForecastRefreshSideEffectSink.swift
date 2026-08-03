import Foundation

/// App-facing hook after a forecast snapshot is persisted.
/// Keeps WidgetKit / notifications out of SunsetHueCore.
public protocol ForecastRefreshSideEffectSink: Sendable {
    func didPersistSnapshot(
        location: SavedLocation,
        previous: CachedLocationSnapshot?,
        current: CachedLocationSnapshot,
        wasSuccessfulNetworkRefresh: Bool
    ) async
}

public struct NoOpForecastRefreshSideEffectSink: ForecastRefreshSideEffectSink {
    public init() {}

    public func didPersistSnapshot(
        location: SavedLocation,
        previous: CachedLocationSnapshot?,
        current: CachedLocationSnapshot,
        wasSuccessfulNetworkRefresh: Bool
    ) async {}
}
