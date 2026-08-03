import Foundation
import SunsetHueCore

protocol NotificationPreferencesStoring: Sendable {
    func load() -> NotificationPreferences
    func save(_ preferences: NotificationPreferences)
}

struct NotificationPreferencesStore: NotificationPreferencesStoring, @unchecked Sendable {
    static let defaultsKey = "notificationPreferences.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> NotificationPreferences {
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            return NotificationPreferences()
        }
        do {
            var prefs = try JSONDecoder().decode(NotificationPreferences.self, from: data)
            if prefs.schemaVersion < NotificationPreferences.currentSchemaVersion {
                prefs.schemaVersion = NotificationPreferences.currentSchemaVersion
            }
            return prefs
        } catch {
            return NotificationPreferences()
        }
    }

    func save(_ preferences: NotificationPreferences) {
        var prefs = preferences
        prefs.schemaVersion = NotificationPreferences.currentSchemaVersion
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

protocol NotificationDeliveryLedgerStoring: Sendable {
    func load() -> [NotificationLedgerEntry]
    func save(_ entries: [NotificationLedgerEntry])
}

struct NotificationDeliveryLedgerStore: NotificationDeliveryLedgerStoring, @unchecked Sendable {
    static let defaultsKey = "notificationDeliveryLedger.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [NotificationLedgerEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
        let decoded = (try? JSONDecoder().decode([NotificationLedgerEntry].self, from: data)) ?? []
        return NotificationDeliveryLedgerMath.prune(decoded)
    }

    func save(_ entries: [NotificationLedgerEntry]) {
        let pruned = NotificationDeliveryLedgerMath.prune(entries)
        guard let data = try? JSONEncoder().encode(pruned) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func record(_ key: NotificationOccurrenceKey) {
        var entries = load()
        entries.append(NotificationLedgerEntry(key: key))
        save(entries)
    }
}
