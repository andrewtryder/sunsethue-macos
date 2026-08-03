import SwiftUI

struct QualityBadge: View {
    let style: WidgetQualityStyle

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(style.status)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(style.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(style.tint.opacity(0.14), in: Capsule())
            .overlay {
                if contrast == .increased {
                    Capsule()
                        .stroke(style.tint, lineWidth: 1)
                }
            }
            .accessibilityLabel("Forecast quality")
            .accessibilityValue("\(style.percentage), \(style.status)")
    }
}
