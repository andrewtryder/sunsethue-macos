import XCTest
@testable import SunsetHueCore

final class ResponseParserTests: XCTestCase {
    func testSuccessfulSunsetResponseParsing() throws {
        let data = try fixture("event_full")
        let forecast = try ResponseParser.parseEventForecast(data: data, expectedEventType: .sunset)
        XCTAssertEqual(forecast.eventType, .sunset)
        XCTAssertTrue(forecast.modelData)
        XCTAssertEqual(forecast.quality, 0.45)
        XCTAssertEqual(forecast.cloudCover, 0.32)
        XCTAssertEqual(forecast.qualityText, "Good")
        XCTAssertEqual(forecast.direction, 256.7)
        XCTAssertNotNil(forecast.eventTime)
        XCTAssertNotNil(forecast.blueHour?.start)
        XCTAssertNotNil(forecast.goldenHour?.end)
        XCTAssertEqual(forecast.location.latitude, 40.7128)
    }

    func testSuccessfulSunriseWithoutModelData() throws {
        let data = try fixture("event_without_model_data")
        let forecast = try ResponseParser.parseEventForecast(data: data, expectedEventType: .sunrise)
        XCTAssertEqual(forecast.eventType, .sunrise)
        XCTAssertFalse(forecast.modelData)
        XCTAssertNil(forecast.quality)
        XCTAssertNil(forecast.cloudCover)
        XCTAssertEqual(forecast.direction, 60.3)
        XCTAssertNotNil(forecast.blueHour)
        XCTAssertNil(forecast.blueHour?.start)
        XCTAssertNil(forecast.blueHour?.end)
    }

    func testUnknownJSONFieldsAreIgnored() throws {
        var payload = try fixtureJSON("event_full")
        payload["unexpected_top"] = "ok"
        var data = payload["data"] as! [String: Any]
        data["extra_field"] = 123
        payload["data"] = data
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        let forecast = try ResponseParser.parseEventForecast(data: encoded, expectedEventType: .sunset)
        XCTAssertEqual(forecast.quality, 0.45)
    }

    func testInvalidQualityRange() throws {
        var payload = try fixtureJSON("event_full")
        var data = payload["data"] as! [String: Any]
        data["quality"] = 1.2
        payload["data"] = data
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try ResponseParser.parseEventForecast(data: encoded, expectedEventType: .sunset)) { error in
            XCTAssertEqual(error as? SunsetHueError, .invalidResponse("invalid_quality"))
        }
    }

    func testInvalidCloudCoverRange() throws {
        var payload = try fixtureJSON("event_full")
        var data = payload["data"] as! [String: Any]
        data["cloud_cover"] = -0.1
        payload["data"] = data
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try ResponseParser.parseEventForecast(data: encoded, expectedEventType: .sunset))
    }

    func testDirectionNormalizationOf360() throws {
        var payload = try fixtureJSON("event_full")
        var data = payload["data"] as! [String: Any]
        data["direction"] = 360
        payload["data"] = data
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        let forecast = try ResponseParser.parseEventForecast(data: encoded, expectedEventType: .sunset)
        XCTAssertEqual(forecast.direction, 0)
    }

    func testInvalidTimestamp() {
        XCTAssertThrowsError(try ResponseParser.parseDateTime("2026-13-40T99:99:99Z")) { error in
            XCTAssertEqual(error as? SunsetHueError, .invalidResponse("invalid_timestamp"))
        }
    }

    func testMissingTimeZoneOffsetRejected() {
        XCTAssertThrowsError(try ResponseParser.parseDateTime("2026-08-01T12:00:00")) { error in
            XCTAssertEqual(error as? SunsetHueError, .invalidResponse("timestamp_missing_timezone"))
        }
    }

    func testMalformedMagicHourArray() throws {
        var payload = try fixtureJSON("event_full")
        var data = payload["data"] as! [String: Any]
        data["magics"] = ["golden_hour": ["2026-08-01T22:44:00.000Z"]]
        payload["data"] = data
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try ResponseParser.parseEventForecast(data: encoded, expectedEventType: .sunset)) { error in
            XCTAssertEqual(error as? SunsetHueError, .invalidResponse("invalid_golden_hour"))
        }
    }

    func testBoolRejectedAsNumber() throws {
        var payload = try fixtureJSON("event_full")
        var data = payload["data"] as! [String: Any]
        data["quality"] = true
        payload["data"] = data
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try ResponseParser.parseEventForecast(data: encoded, expectedEventType: .sunset))
    }

    func testIntegerZeroQualityAndUnitCloudCoverParse() throws {
        // Live API returns JSON integers such as quality: 0 and cloud_cover: 1.
        // Swift's `is Bool` incorrectly treats those NSNumbers as Bool.
        let json = """
        {
          "time": "2026-08-02T01:26:47.565Z",
          "location": {"latitude": 42.90729, "longitude": -71.15149},
          "grid_location": {"latitude": 42.75, "longitude": -71.25},
          "data": {
            "type": "sunset",
            "model_data": true,
            "quality": 0,
            "cloud_cover": 1,
            "quality_text": "Poor",
            "time": "2026-08-02T00:07:00.000Z",
            "direction": 296.1,
            "magics": {
              "blue_hour": ["2026-08-02T00:34:00.000Z", "2026-08-02T00:48:00.000Z"],
              "golden_hour": ["2026-08-01T23:51:00.000Z", "2026-08-02T00:26:00.000Z"]
            }
          }
        }
        """.data(using: .utf8)!
        let forecast = try ResponseParser.parseEventForecast(data: json, expectedEventType: .sunset)
        XCTAssertEqual(forecast.quality, 0)
        XCTAssertEqual(forecast.cloudCover, 1)
        XCTAssertEqual(forecast.qualityText, "Poor")
        XCTAssertTrue(forecast.modelData)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        guard let url else {
            throw NSError(domain: "tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }

    private func fixtureJSON(_ name: String) throws -> [String: Any] {
        let data = try fixture(name)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
