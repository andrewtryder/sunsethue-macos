import XCTest
@testable import SunsetHueCore

final class MenuBarStatusFormattingTests: XCTestCase {
    private let timeZone = PreviewFixtures.sampleTimeZone

    func testLabelIncludesLocationEventAndQualityByDefault() {
        let status = MenuBarStatus(
            locationName: "Sandown",
            eventType: .sunset,
            quality: 0.82,
            eventTime: Date(),
            timeZone: timeZone,
            message: nil
        )

        let text = MenuBarStatusFormatting.labelText(
            for: status,
            style: .locationEventQuality
        )

        XCTAssertEqual(text, "Sandown · Sunset 82.0%")
        XCTAssertEqual(status.symbolName, "sunset.fill")
    }

    func testAllDisplayStyles() {
        let eventTime = Date()
        let status = MenuBarStatus(
            locationName: "Sandown",
            eventType: .sunrise,
            quality: 0.64,
            eventTime: eventTime,
            timeZone: timeZone,
            message: nil
        )

        XCTAssertEqual(
            MenuBarStatusFormatting.labelText(for: status, style: .eventQuality),
            "Sunrise 64.0%"
        )
        XCTAssertEqual(
            MenuBarStatusFormatting.labelText(for: status, style: .iconOnly),
            ""
        )
        XCTAssertEqual(
            MenuBarStatusFormatting.labelText(for: status, style: .locationEventQuality),
            "Sandown · Sunrise 64.0%"
        )
        let withTime = MenuBarStatusFormatting.labelText(for: status, style: .locationEventQualityTime)
        XCTAssertTrue(withTime.hasPrefix("Sandown · Sunrise 64.0% · "))
        XCTAssertEqual(status.symbolName, "sunrise.fill")
    }

    func testLongNamesUsePredictableTruncation() {
        let long = String(repeating: "A", count: 40)
        let truncated = MenuBarStatusFormatting.truncatedLocationName(long)
        XCTAssertEqual(truncated.count, MenuBarStatusFormatting.maxLocationNameLength)
        XCTAssertTrue(truncated.hasSuffix("…"))
    }

    func testLabelPrefersMessageOverEvent() {
        let status = MenuBarStatus(
            locationName: "Sandown",
            eventType: nil,
            quality: nil,
            eventTime: nil,
            message: "API key needed",
            snapshotStatus: .authenticationRequired
        )

        XCTAssertEqual(
            MenuBarStatusFormatting.labelText(for: status, style: .locationEventQuality),
            "API key needed"
        )
        XCTAssertEqual(status.symbolName, "key.slash")
    }

    func testAccessibilityIncludesLocationEventQualityAndTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.startOfDay(for: Date())
        let sunset = PreviewFixtures.excellentSunset(on: day)
        let status = MenuBarStatus(
            locationName: "Sandown",
            eventType: .sunset,
            quality: 0.82,
            eventTime: sunset.eventTime,
            timeZone: timeZone,
            message: nil
        )

        let label = MenuBarStatusFormatting.accessibilityLabel(for: status, style: .iconOnly)
        XCTAssertTrue(label.contains("Sandown"))
        XCTAssertTrue(label.contains("sunset"))
        XCTAssertTrue(label.contains("82.0 percent") || label.contains("quality"))
        XCTAssertTrue(label.contains("at "))
    }

    func testQualityTierFallbackBands() {
        XCTAssertEqual(MenuBarStatusFormatting.qualityTierName(quality: 0.1), "Poor")
        XCTAssertEqual(MenuBarStatusFormatting.qualityTierName(quality: 0.4), "Fair")
        XCTAssertEqual(MenuBarStatusFormatting.qualityTierName(quality: 0.6), "Good")
        XCTAssertEqual(MenuBarStatusFormatting.qualityTierName(quality: 0.9), "Excellent")
        XCTAssertEqual(
            MenuBarStatusFormatting.qualityTierName(quality: 0.1, qualityText: "Custom"),
            "Custom"
        )
    }

    func testSymbolMappingForFailures() {
        XCTAssertEqual(
            MenuBarStatus(
                locationName: "X",
                eventType: nil,
                quality: nil,
                eventTime: nil,
                message: "Rate limited",
                snapshotStatus: .rateLimited(retryAfter: nil)
            ).symbolName,
            "clock.badge.exclamationmark"
        )
        XCTAssertEqual(
            MenuBarStatus(
                locationName: "X",
                eventType: nil,
                quality: nil,
                eventTime: nil,
                message: "Unavailable",
                snapshotStatus: .temporarilyUnavailable
            ).symbolName,
            "exclamationmark.triangle"
        )
    }

    func testCompactPercentageFormatting() {
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 0.824), "82%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 0.826), "83%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 0.0), "0%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 1.0), "100%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: nil), "—")
    }

    func testCompactDayTimeLabelFormatting() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let today = cal.startOfDay(for: Date())
        let todayEvent = today.addingTimeInterval(3600 * 19 + 58 * 60) // 7:58 PM
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let tomorrowEvent = tomorrow.addingTimeInterval(3600 * 5 + 42 * 60) // 5:42 AM
        let futureDay = cal.date(byAdding: .day, value: 3, to: today)!
        let futureEvent = futureDay.addingTimeInterval(3600 * 6 + 15 * 60)

        let todayText = MenuBarStatusFormatting.compactDayTimeLabel(eventTime: todayEvent, timeZone: timeZone, now: today.addingTimeInterval(3600 * 12))
        XCTAssertFalse(todayText.contains("Today"))
        XCTAssertTrue(todayText.contains("7:58") || todayText.contains("19:58"))

        let tomorrowText = MenuBarStatusFormatting.compactDayTimeLabel(eventTime: tomorrowEvent, timeZone: timeZone, now: today.addingTimeInterval(3600 * 12))
        XCTAssertTrue(tomorrowText.hasPrefix("Tomorrow "))

        let futureText = MenuBarStatusFormatting.compactDayTimeLabel(eventTime: futureEvent, timeZone: timeZone, now: today.addingTimeInterval(3600 * 12))
        let dayFormatter = DateFormatter()
        dayFormatter.timeZone = timeZone
        dayFormatter.setLocalizedDateFormatFromTemplate("EEE")
        let dayName = dayFormatter.string(from: futureEvent)
        XCTAssertTrue(futureText.hasPrefix("\(dayName) "))
    }
}

