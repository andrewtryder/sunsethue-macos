import SwiftUI
import SunsetHueCore

/// Shared quality bands for app + widget surfaces.
struct QualityStyle: Equatable {
    let percentage: String
    let status: String
    let tint: Color
    let tone: StatusTone

    static func resolve(
        quality: Double?,
        qualityText: String?
    ) -> QualityStyle {
        guard let quality else {
            return QualityStyle(
                percentage: "—",
                status: qualityText ?? "Unavailable",
                tint: .secondary,
                tone: .neutral
            )
        }

        let percentage = PresentationFormatting.percentage(fromNormalized: quality) ?? "—"

        let fallbackStatus: String
        let tint: Color
        let tone: StatusTone

        switch quality {
        case ..<0.25:
            fallbackStatus = "Poor"
            tint = .red
            tone = .negative
        case ..<0.50:
            fallbackStatus = "Fair"
            tint = .orange
            tone = .warning
        case ..<0.75:
            fallbackStatus = "Good"
            tint = .blue
            tone = .info
        default:
            fallbackStatus = "Excellent"
            tint = .green
            tone = .positive
        }

        return QualityStyle(
            percentage: percentage,
            status: qualityText ?? fallbackStatus,
            tint: tint,
            tone: tone
        )
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
        case .positive: return .green
        case .warning: return .orange
        case .negative: return .red
        case .info: return .blue
        case .neutral: return .secondary
        }
    }
}

extension EventType {
    var iconColor: Color {
        switch self {
        case .sunrise: return .orange
        case .sunset: return .pink
        }
    }
}

