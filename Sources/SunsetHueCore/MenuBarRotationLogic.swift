import Foundation

/// Pure rotation helpers for the menu-bar label. Does not mutate selectedLocationID.
public enum MenuBarRotationLogic: Sendable {
    /// Locations that currently have a usable matching future forecast.
    public static func usableLocations(
        locations: [SavedLocation],
        snapshots: [UUID: CachedLocationSnapshot],
        selection: MenuBarEventSelection,
        now: Date
    ) -> [SavedLocation] {
        locations.filter { location in
            MenuBarForecastResolver.resolve(
                location: location,
                snapshot: snapshots[location.id],
                selection: selection,
                now: now
            ) != nil
        }
    }

    /// Ordered candidates for rotation: usable locations when any exist, otherwise the full list.
    public static func rotationCandidates(
        locations: [SavedLocation],
        snapshots: [UUID: CachedLocationSnapshot],
        selection: MenuBarEventSelection,
        now: Date
    ) -> [SavedLocation] {
        let usable = usableLocations(
            locations: locations,
            snapshots: snapshots,
            selection: selection,
            now: now
        )
        return usable.isEmpty ? locations : usable
    }

    /// Deterministic index from elapsed time and interval. Stable for a fixed candidate ID list.
    public static func rotationIndex(
        candidateCount: Int,
        intervalSeconds: Int,
        now: Date,
        epoch: Date = Date(timeIntervalSince1970: 0)
    ) -> Int {
        guard candidateCount > 0 else { return 0 }
        let interval = max(1, MenuBarPreferences.clampRotationInterval(intervalSeconds))
        let elapsed = max(0, Int(now.timeIntervalSince(epoch)))
        return (elapsed / interval) % candidateCount
    }

    public static func locationForLabel(
        locations: [SavedLocation],
        snapshots: [UUID: CachedLocationSnapshot],
        preferences: MenuBarPreferences,
        selectedLocationID: UUID?,
        now: Date,
        epoch: Date = Date(timeIntervalSince1970: 0)
    ) -> SavedLocation? {
        guard !locations.isEmpty else { return nil }

        switch preferences.locationMode {
        case .selectedLocation:
            if let selectedLocationID,
               let selected = locations.first(where: { $0.id == selectedLocationID }) {
                return selected
            }
            return locations.first

        case .rotateLocations:
            let candidates = rotationCandidates(
                locations: locations,
                snapshots: snapshots,
                selection: preferences.eventSelection,
                now: now
            )
            guard !candidates.isEmpty else { return locations.first }
            let index = rotationIndex(
                candidateCount: candidates.count,
                intervalSeconds: preferences.rotationIntervalSeconds,
                now: now,
                epoch: epoch
            )
            return candidates[index]
        }
    }

    /// Next wall-clock date when the label should re-evaluate (rotation tick and/or next event).
    public static func nextWakeDate(
        locations: [SavedLocation],
        snapshots: [UUID: CachedLocationSnapshot],
        preferences: MenuBarPreferences,
        selectedLocationID: UUID?,
        now: Date,
        epoch: Date = Date(timeIntervalSince1970: 0)
    ) -> Date {
        var candidates: [Date] = []

        if preferences.locationMode == .rotateLocations, locations.count > 1 {
            let interval = TimeInterval(MenuBarPreferences.clampRotationInterval(preferences.rotationIntervalSeconds))
            let elapsed = max(0, now.timeIntervalSince(epoch))
            let nextTickOffset = (floor(elapsed / interval) + 1) * interval
            candidates.append(epoch.addingTimeInterval(nextTickOffset))
        }

        if let location = locationForLabel(
            locations: locations,
            snapshots: snapshots,
            preferences: preferences,
            selectedLocationID: selectedLocationID,
            now: now,
            epoch: epoch
        ),
           let item = MenuBarForecastResolver.resolve(
            location: location,
            snapshot: snapshots[location.id],
            selection: preferences.eventSelection,
            now: now
           ) {
            candidates.append(item.eventTime.addingTimeInterval(1))
        }

        // Fallback poll so stale/unavailable states can recover without rotation.
        candidates.append(now.addingTimeInterval(60))

        return candidates.min() ?? now.addingTimeInterval(60)
    }
}
