import SwiftUI

/// Capsule status pill used for quality tiers and settings status.
struct StatusBadge: View {
    let title: String
    let tone: StatusTone
    var accessibilityLabelText: String = "Status"
    var accessibilityValueText: String?

    @Environment(\.colorSchemeContrast) private var contrast

    init(
        title: String,
        tone: StatusTone,
        accessibilityLabelText: String = "Status",
        accessibilityValueText: String? = nil
    ) {
        self.title = title
        self.tone = tone
        self.accessibilityLabelText = accessibilityLabelText
        self.accessibilityValueText = accessibilityValueText
    }

    init(quality style: QualityStyle) {
        title = style.status
        tone = style.tone
        accessibilityLabelText = "Forecast quality"
        accessibilityValueText = "\(style.percentage), \(style.status)"
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tone.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tone.tint.opacity(0.14), in: Capsule())
            .overlay {
                if contrast == .increased {
                    Capsule()
                        .stroke(tone.tint, lineWidth: 1)
                }
            }
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityValue(accessibilityValueText ?? title)
    }
}

/// Compatibility wrapper for existing widget call sites.
struct QualityBadge: View {
    let style: QualityStyle

    var body: some View {
        StatusBadge(quality: style)
    }
}
