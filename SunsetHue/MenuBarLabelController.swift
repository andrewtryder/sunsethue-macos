import Foundation
import Combine
import SunsetHueCore

struct MenuBarLabelContent: Equatable, Sendable {
    var symbolName: String
    var title: String
    var accessibilityLabel: String
}

@MainActor
final class MenuBarLabelController: ObservableObject {
    @Published private(set) var content = MenuBarLabelContent(
        symbolName: "sun.horizon",
        title: "SunsetHue",
        accessibilityLabel: "SunsetHue"
    )
    @Published var isPopupPresented = false {
        didSet {
            if oldValue != isPopupPresented {
                restartSchedule()
            }
        }
    }

    private weak var appModel: AppModel?
    private var preferencesStore: MenuBarPreferencesStore?
    private var scheduleTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let epoch = Date(timeIntervalSince1970: 0)

    func attach(appModel: AppModel, preferencesStore: MenuBarPreferencesStore) {
        self.appModel = appModel
        self.preferencesStore = preferencesStore

        cancellables.removeAll()
        appModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshNow()
                self?.restartSchedule()
            }
            .store(in: &cancellables)

        preferencesStore.$preferences
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshNow()
                self?.restartSchedule()
            }
            .store(in: &cancellables)

        refreshNow()
        restartSchedule()
    }

    func refreshNow(at now: Date = Date()) {
        guard let appModel, let preferencesStore else { return }
        let preferences = preferencesStore.preferences
        let locations = appModel.state.locations
        let snapshots = appModel.snapshotsByLocationID

        guard let location = MenuBarRotationLogic.locationForLabel(
            locations: locations,
            snapshots: snapshots,
            preferences: preferences,
            selectedLocationID: appModel.selectedLocationID,
            now: now,
            epoch: epoch
        ) else {
            content = MenuBarLabelContent(
                symbolName: "sun.horizon",
                title: preferences.displayStyle == .iconOnly ? "" : "SunsetHue",
                accessibilityLabel: "SunsetHue"
            )
            return
        }

        let snapshot = snapshots[location.id]
        let item = MenuBarForecastResolver.resolve(
            location: location,
            snapshot: snapshot,
            selection: preferences.eventSelection,
            now: now
        )
        let status = MenuBarStatus.from(
            location: location,
            item: item,
            snapshot: snapshot,
            selection: preferences.eventSelection
        )
        content = MenuBarLabelContent(
            symbolName: status.symbolName,
            title: MenuBarStatusFormatting.labelText(for: status, style: preferences.displayStyle),
            accessibilityLabel: MenuBarStatusFormatting.accessibilityLabel(
                for: status,
                style: preferences.displayStyle
            )
        )
    }

    private func restartSchedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        guard !isPopupPresented else { return }
        guard let appModel, let preferencesStore else { return }

        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let appModel = self.appModel, let preferencesStore = self.preferencesStore else {
                    return
                }
                if self.isPopupPresented { return }

                let now = Date()
                self.refreshNow(at: now)

                let wake = MenuBarRotationLogic.nextWakeDate(
                    locations: appModel.state.locations,
                    snapshots: appModel.snapshotsByLocationID,
                    preferences: preferencesStore.preferences,
                    selectedLocationID: appModel.selectedLocationID,
                    now: now,
                    epoch: self.epoch
                )
                let delay = max(0.5, wake.timeIntervalSince(now))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    deinit {
        scheduleTask?.cancel()
    }
}
