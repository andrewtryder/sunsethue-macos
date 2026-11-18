import SunsetHueCore
import SwiftUI

/// Shared quality bands for app + widget surfaces.
struct QualityStyle: Equatable {
    let tier: ForecastQualityTier?
    let percentage: String
    let status: String
    let tint: Color
    let tone: StatusTone

    static func resolve(
        quality: Double?,
        qualityText: String?
    ) -> QualityStyle {
        guard let tier = ForecastQualityTier.resolve(quality: quality) else {
            return QualityStyle(
                tier: nil,
                percentage: "—",
                status: qualityText ?? "Unavailable",
                tint: .secondary,
                tone: .neutral
            )
        }

        let percentage = PresentationFormatting.percentage(fromNormalized: quality) ?? "—"

        return QualityStyle(
            tier: tier,
            percentage: percentage,
            status: qualityText ?? tier.displayName,
            tint: tier.qualityColor,
            tone: tier.statusTone
        )
    }
}

extension ForecastQualityTier {
    /// Canonical SwiftUI foreground color for a quality tier.
    var qualityColor: Color {
        switch self {
        case .poor: .red
        case .fair: .orange
        case .good: .blue
        case .excellent: .green
        }
    }

    /// Semantic badge tone paired with this quality tier.
    var statusTone: StatusTone {
        switch self {
        case .poor: .negative
        case .fair: .warning
        case .good: .info
        case .excellent: .positive
        }
    }
}

enum StatusTone: Equatable {
    case positive
    case warning
    case negative
    case info
    case neutral

    var tint: Color {
        switch self {
        case .positive: .green
        case .warning: .orange
        case .negative: .red
        case .info: .blue
        case .neutral: .secondary
        }
    }
}

extension EventType {
    var iconColor: Color {
        switch self {
        case .sunrise: .orange
        case .sunset: .pink
        }
    }
}
