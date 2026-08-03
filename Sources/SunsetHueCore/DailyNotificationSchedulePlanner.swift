import Foundation

public struct DailyNotificationSlotPlan: Equatable, Sendable {
    public let identifier: String
    public let deliveryDate: Date
    public let slotNumber: Int
    public let minutesAfterMidnight: Int

    public init(identifier: String, deliveryDate: Date, slotNumber: Int, minutesAfterMidnight: Int) {
        self.identifier = identifier
        self.deliveryDate = deliveryDate
        self.slotNumber = slotNumber
        self.minutesAfterMidnight = minutesAfterMidnight
    }
}

public enum DailyNotificationSchedulePlanner: Sendable {
    public static let identifierPrefix = "daily."

    /// Builds one-shot slots for the next `dayCount` local days (including today if still upcoming).
    public static func plans(
        location: SavedLocation,
        rule: DailySummaryRule,
        now: Date = Date(),
        dayCount: Int = 3
    ) -> [DailyNotificationSlotPlan] {
        guard rule.enabled, let timeZone = location.timeZone else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: now)

        var minutesSlots: [(slot: Int, minutes: Int)] = [(1, clampedMinutes(rule.firstTimeMinutes))]
        if rule.secondTimeEnabled {
            minutesSlots.append((2, clampedMinutes(rule.secondTimeMinutes)))
        }

        var plans: [DailyNotificationSlotPlan] = []
        for dayOffset in 0..<max(0, dayCount) {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let ymd = dayKey(dayStart, calendar: calendar)
            for (slot, minutes) in minutesSlots {
                // Set clock time via components so DST spring-forward days stay at 08:00 local,
                // instead of startOfDay + 8h absolute (which becomes 09:00).
                var components = calendar.dateComponents([.year, .month, .day], from: dayStart)
                components.hour = minutes / 60
                components.minute = minutes % 60
                components.second = 0
                guard let delivery = calendar.date(from: components),
                      delivery > now else { continue }
                let identifier = "\(identifierPrefix)\(location.id.uuidString.lowercased()).\(ymd).\(slot)"
                plans.append(
                    DailyNotificationSlotPlan(
                        identifier: identifier,
                        deliveryDate: delivery,
                        slotNumber: slot,
                        minutesAfterMidnight: minutes
                    )
                )
            }
        }
        return plans.sorted { $0.deliveryDate < $1.deliveryDate }
    }

    public static func dateComponents(
        for plan: DailyNotificationSlotPlan,
        timeZone: TimeZone
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: plan.deliveryDate)
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.hour = plan.minutesAfterMidnight / 60
        components.minute = plan.minutesAfterMidnight % 60
        components.second = 0
        return components
    }

    public static func isDailyIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    public static func dailyIdentifierBelongs(to locationID: UUID, identifier: String) -> Bool {
        identifier.hasPrefix("\(identifierPrefix)\(locationID.uuidString.lowercased()).")
    }

    private static func clampedMinutes(_ value: Int) -> Int {
        min(max(0, value), (23 * 60) + 59)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
