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
}
