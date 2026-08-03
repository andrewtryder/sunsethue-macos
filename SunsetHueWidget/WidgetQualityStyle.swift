import SwiftUI
import SunsetHueCore

struct WidgetQualityStyle {
    let percentage: String
    let status: String
    let tint: Color

    static func resolve(
        quality: Double?,
        qualityText: String?
    ) -> WidgetQualityStyle {
        guard let quality else {
            return WidgetQualityStyle(
                percentage: "—",
                status: qualityText ?? "Unavailable",
                tint: .secondary
            )
        }

        let percentage = PresentationFormatting.percentage(fromNormalized: quality) ?? "—"

        let fallbackStatus: String
        let tint: Color

        switch quality {
        case ..<0.25:
            fallbackStatus = "Poor"
            tint = .red
        case ..<0.50:
            fallbackStatus = "Fair"
            tint = .orange
        case ..<0.75:
            fallbackStatus = "Good"
            tint = .blue
        default:
            fallbackStatus = "Excellent"
            tint = .green
        }

        return WidgetQualityStyle(
            percentage: percentage,
            status: qualityText ?? fallbackStatus,
            tint: tint
        )
    }
}

extension EventType {
    var symbolName: String {
        switch self {
        case .sunrise: return "sunrise.fill"
        case .sunset: return "sunset.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .sunrise: return .orange
        case .sunset: return .pink
        }
    }
}
