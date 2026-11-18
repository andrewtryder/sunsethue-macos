import SunsetHueCore
import SwiftUI

/// Menu-bar status item label with dynamic quality-tier icon tinting and system text styling.
struct SunsetHueMenuBarLabel: View {
    @ObservedObject var labelController: MenuBarLabelController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let iconImage = MenuBarIconRenderer.image(
            for: labelController.content.iconDescriptor,
            appearance: MenuBarAppearanceVariant.from(colorScheme),
            isHighContrast: colorSchemeContrast == .increased
        )
        Group {
            if labelController.content.title.isEmpty {
                Image(nsImage: iconImage)
            } else {
                Label {
                    Text(labelController.content.title)
                } icon: {
                    Image(nsImage: iconImage)
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .accessibilityLabel(labelController.content.accessibilityLabel)
    }
}
