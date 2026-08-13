import SwiftUI
import SunsetHueCore

/// Compact, monochrome, system-rendered menu-bar status item label.
struct SunsetHueMenuBarLabel: View {
    @ObservedObject var labelController: MenuBarLabelController

    var body: some View {
        // Keep system template rendering — no explicit quality/event colors.
        Label(labelController.content.title, systemImage: labelController.content.symbolName)
            .accessibilityLabel(labelController.content.accessibilityLabel)
    }
}
