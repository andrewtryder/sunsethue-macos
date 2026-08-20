import SwiftUI
import AppKit
import SunsetHueCore

/// Expanded menu-bar popup (`.menuBarExtraStyle(.window)`).
struct SunsetHueMenuBarPopoverView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var preferencesStore: MenuBarPreferencesStore
    @ObservedObject var labelController: MenuBarLabelController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appModel.state.locations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(popoverRows) { row in
                            locationRow(row)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: min(CGFloat(max(1, popoverRows.count)) * 38.0 + 8.0, 320.0))
            }

            Divider()
                .padding(.top, 4)
                .padding(.bottom, 6)

            controls
        }
        .padding(.vertical, 8)
        .frame(width: 360)
        .onAppear { labelController.isPopupPresented = true }
        .onDisappear { labelController.isPopupPresented = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SunsetHue menu")
    }

    private var popoverRows: [MenuBarPopoverRow] {
        appModel.menuBarPopoverRows(
            preferences: preferencesStore.preferences,
            now: Date()
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No locations yet")
                .font(.headline)
            Text("Add a location in the main window to see forecasts here.")
                .sunsetHueMuted()
            Button("Open SunsetHue") {
                dismissPopupThen {
                    MainWindowPresenter.present(openWindow: openWindow)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func locationRow(_ row: MenuBarPopoverRow) -> some View {
        Button {
            appModel.selectLocation(id: row.id)
            dismissPopupThen {
                MainWindowPresenter.present(openWindow: openWindow)
            }
        } label: {
            HStack(spacing: 8) {
                // Subtle checkmark indicator for selected location
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .opacity(row.isSelected ? 1 : 0)
                    .frame(width: 12)

                // Location name (strongest emphasis, truncates gracefully)
                Text(row.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if let eventType = row.eventType,
                   let eventLabel = row.eventLabel,
                   let dayTimeLabel = row.dayTimeLabel,
                   let qualityLabel = row.qualityLabel {
                    // Normal forecast row: EVENT | TIME | QUALITY
                    HStack(spacing: 4) {
                        Image(systemName: eventType.symbolName)
                            .foregroundStyle(eventType.iconColor)
                        Text(eventLabel)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .lineLimit(1)

                    Text(dayTimeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)

                    Text(qualityLabel)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(minWidth: 38, alignment: .trailing)
                } else if let statusMessage = row.statusMessage {
                    // Unavailable / Error row
                    HStack(spacing: 4) {
                        if let symbolName = row.statusSymbolName {
                            Image(systemName: symbolName)
                                .foregroundStyle(.secondary)
                        }
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background {
                if row.isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.name)
        .accessibilityValue(row.accessibilityValue)
        .accessibilityHint("Opens this location in SunsetHue")
    }

    private var controls: some View {
        VStack(spacing: 6) {
            Button("Refresh All") {
                appModel.refreshAllFromCommand()
            }
            .controlSize(.small)
            .disabled(appModel.isRefreshing)
            .keyboardShortcut("r", modifiers: [.command])
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button("Open SunsetHue…") {
                    dismissPopupThen {
                        MainWindowPresenter.present(openWindow: openWindow)
                    }
                }
                .controlSize(.small)

                Spacer(minLength: 4)

                Button("Settings…") {
                    dismissPopupThen {
                        SettingsPresenter.present(openSettings: openSettings)
                    }
                }
                .controlSize(.small)
                .keyboardShortcut(",", modifiers: [.command])

                Button("Quit SunsetHue") {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
                .keyboardShortcut("q", modifiers: [.command])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private func dismissPopupThen(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.async(execute: action)
    }
}

enum SettingsPresenter {
    @MainActor
    static func present(openSettings: OpenSettingsAction) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            openSettings()
        }
    }
}
