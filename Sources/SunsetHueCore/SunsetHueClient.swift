import Foundation
import os

public struct SunsetHueClient: Sendable {
    private let transport: any HTTPTransport
    private let apiKey: String
    private let userAgent: String
    private let logger = Logger(subsystem: "com.andrewtryder.SunsetHue", category: "API")

    public init(
        apiKey: String,
        transport: any HTTPTransport = URLSessionTransport(),
        userAgent: String = SunsetHueConstants.userAgent
    ) {
        self.apiKey = apiKey
        self.transport = transport
        self.userAgent = userAgent
    }

    public func fetchEvent(
        coordinates: Coordinates,
        date: Date,
        eventType: EventType,
        forecast: Bool = true,
        timeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) async throws -> EventForecast {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw SunsetHueError.missingCredentials
        }

        let validated = try coordinates.validated()
        var cal = calendar
        cal.timeZone = timeZone
        let components = cal.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw SunsetHueError.invalidRequest
        }
        let dateString = String(format: "%04d-%02d-%02d", year, month, day)

        var componentsURL = URLComponents(
            url: SunsetHueConstants.apiBaseURL.appendingPathComponent(SunsetHueConstants.apiEventPath),
            resolvingAgainstBaseURL: false
        )!
        componentsURL.queryItems = [
            URLQueryItem(name: "latitude", value: String(validated.latitude)),
            URLQueryItem(name: "longitude", value: String(validated.longitude)),
            URLQueryItem(name: "date", value: dateString),
            URLQueryItem(name: "type", value: eventType.rawValue),
            URLQueryItem(name: "forecast", value: forecast ? "true" : "false"),
        ]

        guard let url = componentsURL.url else {
            throw SunsetHueError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: SunsetHueConstants.apiKeyHeader)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = SunsetHueConstants.apiTimeoutSeconds
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false

        let response: HTTPResponse
        do {
            response = try await transport.perform(request)
        } catch let error as SunsetHueError {
            logger.error("Request failed: \(error.diagnosticDescription, privacy: .public)")
            throw error
        }

        try Self.raiseForStatus(response)
        logger.debug("Fetched \(eventType.rawValue, privacy: .public) for local date \(dateString, privacy: .public)")
        return try ResponseParser.parseEventForecast(data: response.body, expectedEventType: eventType)
    }

    public func testConnection(
        coordinates: Coordinates,
        timeZone: TimeZone,
        now: Date = Date()
    ) async throws -> EventForecast {
        try await fetchEvent(
            coordinates: coordinates,
            date: now,
            eventType: .sunset,
            forecast: true,
            timeZone: timeZone
        )
    }

    static func raiseForStatus(_ response: HTTPResponse) throws {
        let status = response.statusCode
        if (200..<300).contains(status) {
            return
        }
        if status == 401 || status == 403 {
            throw SunsetHueError.authentication
        }
        if status == 429 {
            let retry = ResponseParser.parseRetryAfter(response.headerValue(forName: "Retry-After"))
            throw SunsetHueError.rateLimited(retryAfter: retry)
        }
        if status == 400 || status == 422 {
            throw SunsetHueError.invalidRequest
        }
        if (500..<600).contains(status) {
            throw SunsetHueError.serviceUnavailable
        }
        throw SunsetHueError.unexpectedStatus(status)
    }

    /// Returns true if a string appears to contain an API key-like secret (for test redaction checks).
    public static func containsRedactedSecret(_ text: String, apiKey: String) -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return text.contains(trimmed)
    }
}
