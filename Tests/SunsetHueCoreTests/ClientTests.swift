import XCTest
@testable import SunsetHueCore

final class ClientTests: XCTestCase {
    private let apiKey = "test-key-not-real"
    private let coordinates = Coordinates(latitude: 40.7128, longitude: -74.006)
    private let timeZone = TimeZone(identifier: "America/New_York")!

    func testAuthenticationStatusMapping() async {
        let transport = MockHTTPTransport(stubs: [.init(statusCode: 401, body: Data())])
        let client = SunsetHueClient(apiKey: apiKey, transport: transport)
        do {
            _ = try await client.fetchEvent(
                coordinates: coordinates,
                date: Date(),
                eventType: .sunset,
                timeZone: timeZone
            )
            XCTFail("Expected auth error")
        } catch let error as SunsetHueError {
            XCTAssertEqual(error, .authentication)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testForbiddenMapsToAuthentication() async {
        let transport = MockHTTPTransport(stubs: [.init(statusCode: 403, body: Data())])
        let client = SunsetHueClient(apiKey: apiKey, transport: transport)
        await assertError(client, equals: .authentication)
    }

    func testInvalidRequestStatusMapping() async {
        let transport = MockHTTPTransport(stubs: [.init(statusCode: 422, body: Data())])
        let client = SunsetHueClient(apiKey: apiKey, transport: transport)
        await assertError(client, equals: .invalidRequest)
    }

    func testRateLimitParsingFromSeconds() async {
        let transport = MockHTTPTransport(stubs: [
            .init(statusCode: 429, headers: ["Retry-After": "120"], body: Data()),
        ])
        let client = SunsetHueClient(apiKey: apiKey, transport: transport)
        await assertError(client, equals: .rateLimited(retryAfter: 120))
    }

    func testRateLimitParsingFromHTTPDate() async {
        let future = Date().addingTimeInterval(3600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        let header = formatter.string(from: future)
        let transport = MockHTTPTransport(stubs: [
            .init(statusCode: 429, headers: ["Retry-After": header], body: Data()),
        ])
        let client = SunsetHueClient(apiKey: apiKey, transport: transport)
        do {
            _ = try await client.fetchEvent(
                coordinates: coordinates,
                date: Date(),
                eventType: .sunset,
                timeZone: timeZone
            )
            XCTFail("Expected rate limit")
        } catch let SunsetHueError.rateLimited(retryAfter) {
            XCTAssertNotNil(retryAfter)
            XCTAssertGreaterThan(retryAfter!, 3500)
            XCTAssertLessThanOrEqual(retryAfter!, SunsetHueConstants.maxRetryAfterSeconds)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testRetryAfterCappedAt24Hours() {
        let parsed = ResponseParser.parseRetryAfter("999999")
        XCTAssertEqual(parsed, SunsetHueConstants.maxRetryAfterSeconds)
    }

    func testResponseSizeEnforcement() async {
        let oversized = Data(repeating: 0x41, count: SunsetHueConstants.maxResponseBytes + 1)
        let transport = MockHTTPTransport(stubs: [.init(statusCode: 200, body: oversized)])
        let client = SunsetHueClient(apiKey: apiKey, transport: transport)
        await assertError(client, equals: .oversizedResponse)
    }

    func testServiceUnavailable() async {
        let transport = MockHTTPTransport(stubs: [.init(statusCode: 503, body: Data())])
        let client = SunsetHueClient(apiKey: apiKey, transport: transport)
        await assertError(client, equals: .serviceUnavailable)
    }

    func testAPIKeyRedactionInErrorsAndDiagnostics() {
        let secret = "super-secret-api-key-value"
        let error = SunsetHueError.authentication
        XCTAssertFalse(SunsetHueClient.containsRedactedSecret(error.userMessage, apiKey: secret))
        XCTAssertFalse(SunsetHueClient.containsRedactedSecret(error.diagnosticDescription, apiKey: secret))
    }

    func testSuccessfulFetchUsesHeaderAndDoesNotEmbedKeyInURL() async throws {
        let body = try loadFixture("event_full")
        let transport = MockHTTPTransport(stubs: [.init(statusCode: 200, body: body)])
        let client = SunsetHueClient(apiKey: apiKey, transport: transport)
        let forecast = try await client.fetchEvent(
            coordinates: coordinates,
            date: Date(),
            eventType: .sunset,
            timeZone: timeZone
        )
        XCTAssertEqual(forecast.eventType, .sunset)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), apiKey)
        XCTAssertFalse(request.url?.absoluteString.contains(apiKey) ?? true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), SunsetHueConstants.userAgent)
    }

    func testMissingCredentials() async {
        let transport = MockHTTPTransport()
        let client = SunsetHueClient(apiKey: "   ", transport: transport)
        await assertError(client, equals: .missingCredentials)
    }

    private func assertError(_ client: SunsetHueClient, equals expected: SunsetHueError) async {
        do {
            _ = try await client.fetchEvent(
                coordinates: coordinates,
                date: Date(),
                eventType: .sunset,
                timeZone: timeZone
            )
            XCTFail("Expected \(expected)")
        } catch let error as SunsetHueError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }
}
