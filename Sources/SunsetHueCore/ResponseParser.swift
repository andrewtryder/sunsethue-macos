import Foundation

enum ResponseParser {
    static func parseEventForecast(
        data: Data,
        expectedEventType: EventType?
    ) throws -> EventForecast {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SunsetHueError.invalidJSON
        }
        guard let payload = object as? [String: Any] else {
            throw SunsetHueError.invalidResponse("root_not_object")
        }
        return try parseEventForecast(payload: payload, expectedEventType: expectedEventType)
    }

    static func parseEventForecast(
        payload: [String: Any],
        expectedEventType: EventType?
    ) throws -> EventForecast {
        let data = try requiredObject(payload, key: "data")
        let typeString = try requiredString(data, key: "type")
        guard let eventType = EventType(rawValue: typeString) else {
            throw SunsetHueError.invalidResponse("unsupported_event_type")
        }
        if let expectedEventType, eventType != expectedEventType {
            throw SunsetHueError.invalidResponse("event_type_mismatch")
        }
        let modelData = try requiredBool(data, key: "model_data")
        return EventForecast(
            responseTime: try parseDateTime(try requiredString(payload, key: "time")),
            location: try parseCoordinates(try requiredObject(payload, key: "location")),
            gridLocation: try parseCoordinates(try requiredObject(payload, key: "grid_location")),
            eventType: eventType,
            modelData: modelData,
            quality: try optionalBoundedNumber(data, key: "quality", minimum: 0, maximum: 1),
            qualityText: try optionalString(data, key: "quality_text"),
            cloudCover: try optionalBoundedNumber(data, key: "cloud_cover", minimum: 0, maximum: 1),
            eventTime: try optionalDateTime(data, key: "time"),
            direction: try parseDirection(data),
            blueHour: try optionalMagicWindow(data, name: "blue_hour"),
            goldenHour: try optionalMagicWindow(data, name: "golden_hour")
        )
    }

    static func parseRetryAfter(_ value: String?, now: Date = Date()) -> Int? {
        guard let value, !value.isEmpty else { return nil }
        if let seconds = Int(value) {
            return max(0, min(seconds, SunsetHueConstants.maxRetryAfterSeconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        return max(0, min(seconds, SunsetHueConstants.maxRetryAfterSeconds))
    }

    // MARK: - Private helpers

    private static func requiredObject(_ value: [String: Any], key: String) throws -> [String: Any] {
        guard let item = value[key] as? [String: Any] else {
            throw SunsetHueError.invalidResponse("missing_or_invalid_\(key)")
        }
        return item
    }

    private static func requiredString(_ value: [String: Any], key: String) throws -> String {
        guard let item = value[key] as? String, !item.isEmpty else {
            throw SunsetHueError.invalidResponse("missing_or_invalid_\(key)")
        }
        return item
    }

    private static func requiredBool(_ value: [String: Any], key: String) throws -> Bool {
        guard let item = value[key] else {
            throw SunsetHueError.invalidResponse("missing_or_invalid_\(key)")
        }
        // JSONSerialization bridges true/false as __NSCFBoolean (NSNumber subclass).
        // Do not use `as? Bool` / `is Bool` alone — integer 0/1 also bridge to Bool.
        guard isJSONBool(item), let bool = item as? Bool else {
            throw SunsetHueError.invalidResponse("missing_or_invalid_\(key)")
        }
        return bool
    }

    private static func optionalString(_ value: [String: Any], key: String) throws -> String? {
        guard let item = value[key] else { return nil }
        guard let string = item as? String else {
            throw SunsetHueError.invalidResponse("invalid_\(key)")
        }
        return string
    }

    private static func optionalNumber(_ value: [String: Any], key: String) throws -> Double? {
        guard let item = value[key], !(item is NSNull) else { return nil }
        // Reject real JSON booleans only. Integer 0/1 must remain valid numbers
        // (live SunsetHue responses use quality: 0 and cloud_cover: 1).
        if isJSONBool(item) {
            throw SunsetHueError.invalidResponse("invalid_\(key)")
        }
        if let number = item as? NSNumber {
            let double = number.doubleValue
            guard double.isFinite else {
                throw SunsetHueError.invalidResponse("invalid_\(key)")
            }
            return double
        }
        throw SunsetHueError.invalidResponse("invalid_\(key)")
    }

    private static func isJSONBool(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    private static func optionalBoundedNumber(
        _ value: [String: Any],
        key: String,
        minimum: Double,
        maximum: Double
    ) throws -> Double? {
        guard let item = try optionalNumber(value, key: key) else { return nil }
        guard minimum <= item, item <= maximum else {
            throw SunsetHueError.invalidResponse("invalid_\(key)")
        }
        return item
    }

    private static func requiredBoundedNumber(
        _ value: [String: Any],
        key: String,
        minimum: Double,
        maximum: Double
    ) throws -> Double {
        guard let item = try optionalBoundedNumber(value, key: key, minimum: minimum, maximum: maximum) else {
            throw SunsetHueError.invalidResponse("missing_or_invalid_\(key)")
        }
        return item
    }

    private static func parseCoordinates(_ value: [String: Any]) throws -> Coordinates {
        Coordinates(
            latitude: try requiredBoundedNumber(value, key: "latitude", minimum: -90, maximum: 90),
            longitude: try requiredBoundedNumber(value, key: "longitude", minimum: -180, maximum: 180)
        )
    }

    private static func parseDirection(_ data: [String: Any]) throws -> Double? {
        let direction = try optionalBoundedNumber(data, key: "direction", minimum: 0, maximum: 360)
        if direction == 360 { return 0 }
        return direction
    }

    private static func optionalDateTime(_ value: [String: Any], key: String) throws -> Date? {
        guard let item = value[key], !(item is NSNull) else { return nil }
        guard let string = item as? String else {
            throw SunsetHueError.invalidResponse("invalid_\(key)")
        }
        return try parseDateTime(string)
    }

    static func parseDateTime(_ value: String) throws -> Date {
        // Reject timestamps with no timezone designator.
        if !hasTimeZoneDesignator(value) {
            throw SunsetHueError.invalidResponse("timestamp_missing_timezone")
        }

        let normalized = value.replacingOccurrences(of: "Z", with: "+00:00")
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: normalized) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: normalized) {
            return date
        }
        throw SunsetHueError.invalidResponse("invalid_timestamp")
    }

    private static func hasTimeZoneDesignator(_ value: String) -> Bool {
        if value.hasSuffix("Z") || value.hasSuffix("z") { return true }
        // Offset after the time component, e.g. ...T12:00:00+00:00 or ...T12:00:00-05:00
        guard let tIndex = value.firstIndex(of: "T") else { return false }
        let afterT = value[tIndex...]
        return afterT.contains("+") || afterT.dropFirst().contains("-")
    }

    private static func optionalMagicWindow(_ data: [String: Any], name: String) throws -> MagicHourWindow? {
        guard let magicsValue = data["magics"], !(magicsValue is NSNull) else { return nil }
        guard let magics = magicsValue as? [String: Any] else {
            throw SunsetHueError.invalidResponse("invalid_magics")
        }
        guard let value = magics[name], !(value is NSNull) else { return nil }
        guard let array = value as? [Any], array.count == 2 else {
            throw SunsetHueError.invalidResponse("invalid_\(name)")
        }
        let start = try parseMagicElement(array[0], name: name)
        let end = try parseMagicElement(array[1], name: name)
        return MagicHourWindow(start: start, end: end)
    }

    private static func parseMagicElement(_ value: Any, name: String) throws -> Date? {
        if value is NSNull { return nil }
        guard let string = value as? String else {
            throw SunsetHueError.invalidResponse("invalid_\(name)")
        }
        return try parseDateTime(string)
    }
}
