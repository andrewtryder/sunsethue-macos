import SwiftUI

enum SunsetHueTypography {
    static let sectionHeader = Font.title3.weight(.semibold)
    static let settingsSectionHeader = Font.headline
    static let cardTitle = Font.headline
    static let heroQuality = Font.system(size: 34, weight: .bold, design: .rounded)
}

struct SharedPanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

struct SectionCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SharedPanelBackground()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        contrast == .increased ? Color.primary.opacity(0.35) : Color.clear,
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func sunsetHueMuted() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    func sunsetHueDisabledDim(_ disabled: Bool) -> some View {
        self
            .disabled(disabled)
            .opacity(disabled ? 0.45 : 1)
    }
}
