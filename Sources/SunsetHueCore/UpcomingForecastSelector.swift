import Foundation

/// Chronological upcoming sunrise/sunset selection from a cached forecast bundle.
public enum UpcomingForecastSelector: Sendable {
    /// Returns future forecasts with `eventTime > now`, sorted ascending, capped at `limit`.
    public static func forecasts(
        from bundle: LocationForecastBundle,
        allowedTypes: Set<EventType>,
        now: Date,
        limit: Int
    ) -> [EventForecast] {
        guard limit > 0 else { return [] }
        return Array(
            bundle.forecasts
                .filter { forecast in
                    guard allowedTypes.contains(forecast.eventType),
                          let eventTime = forecast.eventTime else {
                        return false
                    }
                    // Strictly future so the widget advances at sunrise/sunset instant.
                    return eventTime > now
                }
                .sorted { lhs, rhs in
                    (lhs.eventTime ?? .distantFuture) < (rhs.eventTime ?? .distantFuture)
                }
                .prefix(limit)
        )
    }
}
