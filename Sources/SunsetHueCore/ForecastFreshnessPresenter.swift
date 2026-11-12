import Foundation

/// User-facing description of how trustworthy / current a location's displayed forecast is.
/// Pure and deterministic so it can be unit-tested and shared by the window, menu bar and diagnostics.
public struct ForecastFreshness: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case noData
        case loading
        /// Fetched within the refresh interval and last refresh succeeded.
        case current
        /// Cached forecast older than its refresh interval; a refresh is pending.
        case cachedAwaitingRefresh
        /// Last attempt failed because the network or service is temporarily unavailable.
        case networkFailure
        case authenticationRequired
        case rateLimited
        /// Fresh data, but the forecast model could not provide quality for some events.
        case modelUnavailable
        /// Location/request rejected or an incompatible response was received.
        case rejected
    }

    public let kind: Kind
    public let headline: String
    /// Secondary explanation, including cached-forecast age when stale data is displayed.
    public let detail: String?
    /// e.g. "Updated 3 hr ago"; nil when nothing has ever been fetched.
    public let ageText: String?
    /// e.g. "Next refresh around 3:40 PM"; nil when no automatic refresh is planned.
    public let nextRefreshText: String?
    public let isRefreshing: Bool
    /// Cached (not necessarily current) forecast values are being shown.
    public let showsCachedForecast: Bool
    public let needsAttention: Bool
    public let symbolName: String
}

public enum ForecastFreshnessPresenter: Sendable {
    public static func describe(
        snapshot: CachedLocationSnapshot?,
        location: SavedLocation?,
        credentialState: CredentialState,
        isRefreshing: Bool,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        displayTimeZone: TimeZone = .current
    ) -> ForecastFreshness {
        guard let snapshot else {
            if isRefreshing {
                return make(.loading, "Loading forecast…", nil, nil, nil, true, false, false, "arrow.triangle.2.circlepath")
            }
            if credentialState == .missing {
                return make(.authenticationRequired, "API key needed",
                            "Add your SunsetHue API key in Settings → Account to load forecasts.",
                            nil, nil, false, false, true, "key.slash")
            }
            return make(.noData, "No forecast yet",
                        "Refresh to fetch sunrise and sunset quality for this location.",
                        nil, nil, false, false, false, "cloud.sun")
        }

        let hasForecasts = !snapshot.forecasts.isEmpty
        let age = hasForecasts ? ageText(from: snapshot.fetchedAt, now: now) : nil
        let updated = age.map { "Updated \($0)" }
        let savedPhrase = age.map { "Showing the saved forecast from \($0)." }
        let next = nextRefreshText(snapshot: snapshot, location: location, now: now, locale: locale, zone: displayTimeZone)

        switch snapshot.status {
        case .current:
            let interval = location?.refreshIntervalHours ?? SunsetHueConstants.defaultRefreshIntervalHours
            if !snapshot.isFresh(refreshIntervalHours: interval, now: now) {
                return make(.cachedAwaitingRefresh, "Saved forecast — refresh pending",
                            savedPhrase.map { "\($0) It will update automatically." } ?? "It will update automatically.",
                            updated, next, isRefreshing, true, false, "clock.arrow.circlepath")
            }
            if snapshot.forecasts.contains(where: { !$0.isQualityAvailable }) {
                return make(.modelUnavailable, "Some forecast model data unavailable",
                            "Timing is available, but quality isn't for every event yet.",
                            updated, next, isRefreshing, false, false, "exclamationmark.circle")
            }
            return make(.current, "Up to date", nil, updated, next, isRefreshing, false, false, "checkmark.circle")

        case .stale:
            return make(.cachedAwaitingRefresh, "Saved forecast — refresh pending",
                        savedPhrase.map { "\($0) Waiting for the next attempt." } ?? "Waiting for the next attempt.",
                        updated, next, isRefreshing, hasForecasts, false, "clock.arrow.circlepath")

        case .authenticationRequired:
            let action = credentialState == .unavailable
                ? "Unlock your Mac so the Keychain is available, then refresh."
                : credentialState == .missing
                    ? "Add your API key in Settings → Account."
                    : "SunsetHue rejected the API key. Check or replace it in Settings → Account."
            let detail = [action, savedPhrase].compactMap { $0 }.joined(separator: " ")
            return make(.authenticationRequired, "API key needs attention", detail, updated, nil,
                        isRefreshing, hasForecasts, true, "key.slash")

        case .rateLimited(let retryAfter):
            var detail = "SunsetHue asked the app to slow down."
            if let retryAfter, retryAfter > now {
                detail += " Next attempt after \(timeString(retryAfter, locale: locale, zone: displayTimeZone))."
            }
            if let savedPhrase { detail += " \(savedPhrase)" }
            return make(.rateLimited, "Rate limited", detail, updated, next, isRefreshing, hasForecasts, true, "hourglass")

        case .temporarilyUnavailable:
            var detail = hasForecasts ? (savedPhrase ?? "") : "No saved forecast is available yet."
            if next != nil { detail += " Retrying automatically." }
            return make(.networkFailure, "Can't reach SunsetHue",
                        detail.trimmingCharacters(in: .whitespaces), updated, next,
                        isRefreshing, hasForecasts, true, "wifi.exclamationmark")

        case .invalidRequest:
            return make(.rejected, "Location was rejected",
                        "Check this location's coordinates and time zone, then refresh.",
                        updated, nil, isRefreshing, hasForecasts, true, "mappin.slash")

        case .invalidResponse:
            var detail = "SunsetHue returned an unexpected response."
            if let savedPhrase { detail += " \(savedPhrase)" }
            return make(.rejected, "Unexpected response", detail, updated, next,
                        isRefreshing, hasForecasts, true, "exclamationmark.triangle")
        }
    }

    /// Compact relative age: "just now", "12 min ago", "3 hr ago", "2 days ago".
    public static func ageText(from date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400:
            return "\(Int(seconds / 3600)) hr ago"
        default:
            let days = Int(seconds / 86_400)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }

    private static func nextRefreshText(
        snapshot: CachedLocationSnapshot,
        location: SavedLocation?,
        now: Date,
        locale: Locale,
        zone: TimeZone
    ) -> String? {
        let interval = location?.refreshIntervalHours ?? SunsetHueConstants.defaultRefreshIntervalHours
        guard let next = snapshot.nextScheduledRefresh(
            refreshIntervalHours: interval,
            timeZone: location?.timeZone,
            now: now
        ) else { return nil }
        if next <= now.addingTimeInterval(60) { return "Next refresh: soon" }
        return "Next refresh around \(timeString(next, locale: locale, zone: zone, now: now))"
    }

    private static func timeString(_ date: Date, locale: Locale, zone: TimeZone, now: Date? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        if let now, !calendar.isDate(date, inSameDayAs: now) {
            formatter.setLocalizedDateFormatFromTemplate("EEE jmm")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("jmm")
        }
        return formatter.string(from: date)
    }

    private static func make(
        _ kind: ForecastFreshness.Kind,
        _ headline: String,
        _ detail: String?,
        _ age: String?,
        _ next: String?,
        _ refreshing: Bool,
        _ cached: Bool,
        _ attention: Bool,
        _ symbol: String
    ) -> ForecastFreshness {
        ForecastFreshness(
            kind: kind,
            headline: headline,
            detail: detail?.isEmpty == true ? nil : detail,
            ageText: age,
            nextRefreshText: next,
            isRefreshing: refreshing,
            showsCachedForecast: cached,
            needsAttention: attention,
            symbolName: symbol
        )
    }
}

