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
                    LazyVStack(spacing: 8) {
                        ForEach(popoverRows) { row in
                            locationCard(row)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
                .frame(maxHeight: min(CGFloat(max(1, popoverRows.count)) * 118, 420))
            }

            Divider()
                .padding(.top, 10)

            controls
        }
        .padding(.vertical, 10)
        .frame(width: 372)
        .onAppear { labelController.isPopupPresented = true }
        .onDisappear { labelController.isPopupPresented = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SunsetHue menu")
    }

    private var popoverRows: [AppModel.MenuBarPopoverRow] {
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
        .padding(.vertical, 4)
    }

    private func locationCard(_ row: AppModel.MenuBarPopoverRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                appModel.selectLocation(id: row.id)
                dismissPopupThen {
                    MainWindowPresenter.present(openWindow: openWindow)
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.name)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if row.isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Selected location")
                        }
                    }

                    if let item = row.item {
                        let style = QualityStyle.resolve(quality: item.quality, qualityText: item.qualityText)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Label {
                                Text(item.eventType.displayName)
                            } icon: {
                                Image(systemName: item.eventType.symbolName)
                                    .foregroundStyle(item.eventType.iconColor)
                            }
                            .font(.subheadline)

                            Spacer(minLength: 4)

                            Text(style.percentage)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(style.tint)
                                .accessibilityLabel("Forecast quality")
                                .accessibilityValue("\(style.percentage), \(style.status)")

                            StatusBadge(quality: style)
                        }

                        Text("\(row.dayLabel) at \(row.timeLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let magic = row.magicHoursLabel {
                            Text(magic)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 6) {
                            Text(row.updatedLabel)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if item.isStale {
                                StatusBadge(title: "Stale", tone: .warning, accessibilityLabelText: "Cache status")
                            }
                        }
                    } else {
                        Text(row.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let tone = row.statusTone {
                            StatusBadge(title: row.statusBadgeTitle ?? "Status", tone: tone)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.name)
            .accessibilityValue(row.accessibilityValue)
            .accessibilityHint("Opens this location in SunsetHue")

            HStack {
                Spacer()
                Button("Refresh") {
                    appModel.refreshLocationFromMenuBar(id: row.id)
                }
                .controlSize(.mini)
                .disabled(appModel.isRefreshing || appModel.refreshingLocationIDs.contains(row.id))
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(row.isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.65))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(row.isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
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
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
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
