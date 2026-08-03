import Foundation

public enum PresentationFormatting: Sendable {
    /// Convert a normalized 0...1 value to a one-decimal percentage for display only.
    public static func percentage(fromNormalized value: Double?) -> String? {
        guard let value else { return nil }
        let percent = (value * 1000).rounded() / 10
        return String(format: "%.1f%%", percent)
    }

    public static func percentageValue(fromNormalized value: Double?) -> Double? {
        guard let value else { return nil }
        return (value * 1000).rounded() / 10
    }

    public static func directionLabel(_ degrees: Double?) -> String? {
        guard let degrees else { return nil }
        return String(format: "%.0f°", degrees)
    }

    public static func timeString(
        _ date: Date?,
        timeZone: TimeZone,
        locale: Locale = .autoupdatingCurrent,
        style: DateFormatter.Style = .short
    ) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = style
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    public static func dateLabel(_ date: Date?, timeZone: TimeZone) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    public static func relativeDayLabel(dayOffset: Int, reference: Date = Date(), timeZone: TimeZone) -> String {
        switch dayOffset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            let calendar = Calendar(identifier: .gregorian)
            var cal = calendar
            cal.timeZone = timeZone
            let day = cal.startOfDay(for: reference).addingTimeInterval(TimeInterval(dayOffset * 86_400))
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
            return formatter.string(from: day)
        }
    }
}
