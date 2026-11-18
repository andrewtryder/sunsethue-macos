import Combine
import Foundation
import SunsetHueCore

@MainActor
final class MenuBarLabelController: ObservableObject {
    @Published private(set) var content = MenuBarLabelContent(
        symbolName: "sun.horizon",
        title: "SunsetHue",
        accessibilityLabel: "SunsetHue"
    )

    /// Presentation state of the `.menuBarExtraStyle(.window)` popup.
    ///
    /// Assignments are idempotent: writing the current value is a no-op (no Combine
    /// emission, no schedule churn), so SwiftUI lifecycle callbacks that fire more
    /// than once for a single presentation transition cannot cause redundant work.
    @Published var isPopupPresented = false {
        willSet {
            guard newValue != isPopupPresented else { return }
            // Run the schedule transition after the value lands to observe the new state.
            Task { @MainActor [weak self] in
                self?.restartSchedule()
            }
        }
    }

    private weak var appModel: AppModel?
    private var preferencesStore: MenuBarPreferencesStore?
    private var scheduleTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let epoch = Date(timeIntervalSince1970: 0)
    private var isAttached = false

    /// Binds the controller to the app model and preference store.
    ///
    /// Called from several SwiftUI lifecycle callbacks (`Window.onAppear`, the
    /// `MenuBarExtra` label's `onAppear`, Settings), which can each fire on scene
    /// changes. Subscriptions are created exactly once; later calls only refresh
    /// content against the (possibly newly created) model objects.
    func attach(appModel: AppModel, preferencesStore: MenuBarPreferencesStore) {
        self.appModel = appModel
        self.preferencesStore = preferencesStore

        if !isAttached {
            isAttached = true
            Publishers.CombineLatest4(
                appModel.$state.map(\.locations).removeDuplicates(),
                appModel.$snapshotsByLocationID.removeDuplicates(),
                appModel.$selectedLocationID.removeDuplicates(),
                preferencesStore.$preferences.removeDuplicates()
            )
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshNow()
                self?.restartSchedule()
            }
            .store(in: &cancellables)
        }

        refreshNow()
        restartSchedule()
    }

    func refreshNow(at now: Date = Date()) {
        guard let appModel, let preferencesStore else { return }
        let next = MenuBarLabelContent.resolve(
            locations: appModel.state.locations,
            snapshots: appModel.snapshotsByLocationID,
            preferences: preferencesStore.preferences,
            selectedLocationID: appModel.selectedLocationID,
            now: now,
            epoch: epoch
        )

        // Skip identical assignments so unchanged label content never triggers a
        // SwiftUI invalidation of the menu bar item or the open popup.
        if next != content {
            content = next
        }
    }

    private func restartSchedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        guard !isPopupPresented, appModel != nil, preferencesStore != nil else { return }

        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let appModel, let preferencesStore else {
                    return
                }
                if isPopupPresented {
                    return
                }

                let now = Date()
                refreshNow(at: now)

                let wake = MenuBarRotationLogic.nextWakeDate(
                    locations: appModel.state.locations,
                    snapshots: appModel.snapshotsByLocationID,
                    preferences: preferencesStore.preferences,
                    selectedLocationID: appModel.selectedLocationID,
                    now: now,
                    epoch: epoch
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
