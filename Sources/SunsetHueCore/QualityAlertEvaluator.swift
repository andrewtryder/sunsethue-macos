import Foundation

public struct QualityAlertCandidate: Equatable, Sendable {
    public let key: NotificationOccurrenceKey
    public let forecast: EventForecast
    public let title: String
    public let body: String

    public init(key: NotificationOccurrenceKey, forecast: EventForecast, title: String, body: String) {
        self.key = key
        self.forecast = forecast
        self.title = title
        self.body = body
    }
}

public enum QualityAlertEvaluator: Sendable {
    /// Returns alerts that should fire for a successful network refresh.
    public static func candidates(
        location: SavedLocation,
        snapshot: CachedLocationSnapshot,
        preferences: NotificationPreferences,
        ledger: [NotificationLedgerEntry],
        wasSuccessfulNetworkRefresh: Bool,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent
    ) -> [QualityAlertCandidate] {
        let rule = preferences.rule(for: location.id).qualityAlert
        guard preferences.notificationsEnabled,
              rule.enabled,
              wasSuccessfulNetworkRefresh,
              snapshot.status == .current,
              let timeZone = location.timeZone else {
            return []
        }

        let allowed = rule.eventMode.allowedTypes.intersection(Set(location.enabledEvents))
        var results: [QualityAlertCandidate] = []

        for forecast in snapshot.forecasts {
            guard allowed.contains(forecast.eventType),
                  let quality = forecast.quality,
                  quality >= rule.threshold else {
                continue
            }
            guard let forecastDate = forecast.forecastDate else { continue }
            let dateKey = localDateKey(forecastDate, timeZone: timeZone)
            let key = NotificationOccurrenceKey(
                ruleID: rule.id,
                revision: rule.revision,
                locationID: location.id,
                eventType: forecast.eventType,
                forecastDate: dateKey
            )
            if NotificationDeliveryLedgerMath.contains(ledger, key: key) {
                continue
            }

            let qualityPercent = PresentationFormatting.percentage(fromNormalized: quality) ?? "—"
            let status = forecast.qualityText ?? "Good"
            let weekday = weekdayName(forecastDate, timeZone: timeZone, locale: locale)
            let time = PresentationFormatting.timeString(forecast.eventTime, timeZone: timeZone, locale: locale) ?? "—"
            let title = "\(status) \(forecast.eventType.displayName.lowercased()) forecast for \(location.name)"
            let body = "\(forecast.eventType.displayName) quality is now \(qualityPercent) for \(weekday) at \(time)."
            results.append(QualityAlertCandidate(key: key, forecast: forecast, title: title, body: body))
        }

        return results
    }

    public static func localDateKey(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func weekdayName(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }
}
