import Foundation
import SunsetHueCore

@MainActor
final class MenuBarPreferencesStore: ObservableObject {
    @Published private(set) var preferences: MenuBarPreferences

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = Self.load(from: defaults)
    }

    func update(_ mutate: (inout MenuBarPreferences) -> Void) {
        var next = preferences
        mutate(&next)
        next.rotationIntervalSeconds = MenuBarPreferences.clampRotationInterval(next.rotationIntervalSeconds)
        next.schemaVersion = MenuBarPreferences.currentSchemaVersion
        preferences = next
        save(next)
    }

    func setPreferences(_ value: MenuBarPreferences) {
        var next = value
        next.rotationIntervalSeconds = MenuBarPreferences.clampRotationInterval(next.rotationIntervalSeconds)
        next.schemaVersion = MenuBarPreferences.currentSchemaVersion
        preferences = next
        save(next)
    }

    private func save(_ value: MenuBarPreferences) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: MenuBarPreferences.storageKey)
        // Stop relying on the legacy single-key style after first write.
        defaults.removeObject(forKey: MenuBarPreferences.legacyDisplayStyleKey)
    }

    private static func load(from defaults: UserDefaults) -> MenuBarPreferences {
        if let data = defaults.data(forKey: MenuBarPreferences.storageKey),
           let decoded = try? JSONDecoder().decode(MenuBarPreferences.self, from: data) {
            var prefs = decoded
            prefs.rotationIntervalSeconds = MenuBarPreferences.clampRotationInterval(prefs.rotationIntervalSeconds)
            prefs.schemaVersion = MenuBarPreferences.currentSchemaVersion
            return prefs
        }

        var prefs = MenuBarPreferences()
        if let legacy = defaults.string(forKey: MenuBarPreferences.legacyDisplayStyleKey),
           let style = MenuBarPreferences.migratedDisplayStyle(fromLegacyRaw: legacy) {
            prefs.displayStyle = style
        }
        return prefs
    }
}
