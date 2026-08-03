import Foundation

public enum TimeZoneCatalog: Sendable {
    public static let unitedStatesCandidates = [
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Los_Angeles",
        "America/Phoenix",
        "America/Anchorage",
        "Pacific/Honolulu",
    ]

    public static let europeCandidates = [
        "Europe/London",
        "Europe/Dublin",
        "Europe/Paris",
        "Europe/Berlin",
        "Europe/Madrid",
        "Europe/Rome",
        "Europe/Amsterdam",
        "Europe/Brussels",
        "Europe/Zurich",
        "Europe/Vienna",
        "Europe/Stockholm",
        "Europe/Oslo",
        "Europe/Copenhagen",
        "Europe/Warsaw",
        "Europe/Prague",
        "Europe/Lisbon",
        "Europe/Athens",
        "Europe/Helsinki",
    ]

    public static var knownIdentifiers: [String] {
        TimeZone.knownTimeZoneIdentifiers.sorted()
    }

    /// Curated US identifiers that exist on this system.
    public static var unitedStates: [String] {
        unitedStatesCandidates.filter { TimeZone(identifier: $0) != nil }
    }

    /// Curated Europe identifiers that exist on this system.
    public static var europe: [String] {
        europeCandidates.filter { TimeZone(identifier: $0) != nil }
    }

    public static var suggested: Set<String> {
        Set(unitedStates + europe)
    }

    public static var remaining: [String] {
        let suggested = suggested
        return knownIdentifiers.filter { !suggested.contains($0) }
    }

    public static func friendlyCity(for identifier: String) -> String {
        identifier
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "_", with: " ")
            ?? identifier
    }

    public static func searchableText(
        for identifier: String,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        let abbreviation = zone.abbreviation(for: now) ?? ""
        let seconds = zone.secondsFromGMT(for: now)
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        let gmt = String(format: "GMT%@%02d:%02d", sign, hours, minutes)
        return [
            identifier,
            abbreviation,
            friendlyCity(for: identifier),
            gmt,
            "GMT\(sign)\(hours)",
        ].joined(separator: " ")
    }

    public static func filter(
        _ identifiers: [String],
        searchText: String,
        now: Date = Date()
    ) -> [String] {
        let valid = identifiers.filter { TimeZone(identifier: $0) != nil }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return valid
        }
        return valid.filter {
            searchableText(for: $0, now: now)
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    public static func displayAbbreviation(
        for identifier: String,
        now: Date = Date()
    ) -> String {
        TimeZone(identifier: identifier)?.abbreviation(for: now) ?? ""
    }

    public static func displayGMTOffset(
        for identifier: String,
        now: Date = Date()
    ) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return "" }
        let seconds = zone.secondsFromGMT(for: now)
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        if minutes == 0 {
            return String(format: "GMT%@%d", sign, hours)
        }
        return String(format: "GMT%@%02d:%02d", sign, hours, minutes)
    }
}
