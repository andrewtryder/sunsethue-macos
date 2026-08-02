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
        minimumIntervalSeconds: Int = SunsetHueConstants.minTimelineReloadSeconds,
        jitterSeconds: Int = 0,
        cacheFetchedAt: Date? = nil
    ) -> Date {
        let hours = SunsetHueConstants.validRefreshIntervalHours.contains(refreshIntervalHours)
            ? refreshIntervalHours
            : SunsetHueConstants.defaultRefreshIntervalHours
        let intervalBase = cacheFetchedAt ?? now
        let intervalDate = intervalBase.addingTimeInterval(TimeInterval(hours * 3600 + max(0, jitterSeconds)))
        let midnightDate = nextMidnightRefresh(timeZone: timeZone, now: now)
            .addingTimeInterval(TimeInterval(max(0, jitterSeconds)))
        var candidates = [intervalDate, midnightDate]
        if let retryAfter = rateLimitRetryAfter {
            let bounded = min(max(0, retryAfter), SunsetHueConstants.maxRetryAfterSeconds)
            candidates.append(now.addingTimeInterval(TimeInterval(bounded)))
        }
        let earliest = candidates.min() ?? intervalDate
        let floor = now.addingTimeInterval(TimeInterval(minimumIntervalSeconds))
        return max(earliest, floor)
    }

    /// Visual-change dates from cached forecasts (sunrise/sunset/golden-hour) plus local midnight.
    public func timelineDisplayDates(
        bundle: LocationForecastBundle?,
        timeZone: TimeZone,
        now: Date = Date(),
        until reloadDate: Date
    ) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var dates: [Date] = [now]
        if let bundle {
            for forecast in bundle.forecasts {
                if let eventTime = forecast.eventTime, eventTime > now, eventTime <= reloadDate {
                    dates.append(eventTime)
                }
                if let start = forecast.goldenHour?.start, start > now, start <= reloadDate {
                    dates.append(start)
                }
                if let end = forecast.goldenHour?.end, end > now, end <= reloadDate {
                    dates.append(end)
                }
            }
        }

        let midnight = nextMidnightRefresh(timeZone: timeZone, now: now, delaySeconds: 0)
        if midnight > now, midnight <= reloadDate {
            dates.append(midnight)
        }

        let unique = Array(Set(dates.map { $0.timeIntervalSinceReferenceDate }))
            .sorted()
            .map { Date(timeIntervalSinceReferenceDate: $0) }
        return unique.filter { $0 >= now && $0 <= reloadDate }
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
