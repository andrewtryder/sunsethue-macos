import Foundation

public struct ForecastDateCalculator: Sendable {
    public init() {}

    public func localCalendarDates(
        dayCount: Int,
        timeZone: TimeZone,
        now: Date = Date()
    ) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: now)
        return (0..<max(0, dayCount)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    public func nextMidnightRefresh(
        timeZone: TimeZone,
        now: Date = Date(),
        delaySeconds: Int = SunsetHueConstants.midnightRefreshDelaySeconds
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
        return startOfTomorrow.addingTimeInterval(TimeInterval(delaySeconds))
    }

    public func preferredTimelineReload(
        refreshIntervalHours: Int,
        timeZone: TimeZone,
        now: Date = Date(),
        rateLimitRetryAfter: Int? = nil,
        minimumIntervalSeconds: Int = SunsetHueConstants.minTimelineReloadSeconds
    ) -> Date {
        let hours = SunsetHueConstants.validRefreshIntervalHours.contains(refreshIntervalHours)
            ? refreshIntervalHours
            : SunsetHueConstants.defaultRefreshIntervalHours
        let intervalDate = now.addingTimeInterval(TimeInterval(hours * 3600))
        let midnightDate = nextMidnightRefresh(timeZone: timeZone, now: now)
        var candidates = [intervalDate, midnightDate]
        if let retryAfter = rateLimitRetryAfter {
            candidates.append(now.addingTimeInterval(TimeInterval(retryAfter)))
        }
        let earliest = candidates.min() ?? intervalDate
        let floor = now.addingTimeInterval(TimeInterval(minimumIntervalSeconds))
        return max(earliest, floor)
    }

    public func dayOffset(
        for forecastDate: Date,
        timeZone: TimeZone,
        now: Date = Date()
    ) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startNow = calendar.startOfDay(for: now)
        let startForecast = calendar.startOfDay(for: forecastDate)
        return calendar.dateComponents([.day], from: startNow, to: startForecast).day
    }
}
