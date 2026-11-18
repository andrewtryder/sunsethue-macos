import Foundation

/// Canonical forecast quality bands mapped from a normalized `0...1` quality score.
public enum ForecastQualityTier: String, Codable, Sendable, CaseIterable, Comparable {
    case poor
    case fair
    case good
    case excellent

    private var rank: Int {
        switch self {
        case .poor: 0
        case .fair: 1
        case .good: 2
        case .excellent: 3
        }
    }

    public static func < (lhs: ForecastQualityTier, rhs: ForecastQualityTier) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Human-readable label for fallback status text and accessibility announcements.
    public var displayName: String {
        switch self {
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }

    /// Validates and clamps a raw quality value into `0...1`.
    /// Non-finite values (`NaN`, infinity) are rejected and return `nil`.
    public static func normalizedQuality(_ rawQuality: Double?) -> Double? {
        guard let rawQuality, rawQuality.isFinite else { return nil }
        return min(1.0, max(0.0, rawQuality))
    }

    /// Resolves a raw quality score to a deterministic quality tier, or `nil` when missing/non-finite.
    public static func resolve(quality: Double?) -> ForecastQualityTier? {
        guard let normalized = normalizedQuality(quality) else { return nil }
        switch normalized {
        case ..<0.25:
            return .poor
        case ..<0.50:
            return .fair
        case ..<0.75:
            return .good
        default:
            return .excellent
        }
    }

    /// Resolves the quality tier for an `EventForecast` when model data is available and quality is valid.
    public static func resolve(forecast: EventForecast?) -> ForecastQualityTier? {
        guard let forecast, forecast.isQualityAvailable else { return nil }
        return resolve(quality: forecast.quality)
    }
}
