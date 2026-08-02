import XCTest
@testable import SunsetHueCore

/// Streams a large body without a trustworthy Content-Length (or with a lying small one).
private final class CancelCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        value += 1
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        value = 0
    }
}

final class OversizedStreamURLProtocol: URLProtocol, @unchecked Sendable {
    static let markerHost = "oversized.sunsethue.test"
    private static let cancelCounter = CancelCounter()

    static var cancelCount: Int { cancelCounter.count }

    static func reset() {
        cancelCounter.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == markerHost
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                // Lie small so early Content-Length reject does not fire; body still exceeds limit.
                "Content-Length": "64",
                "Content-Type": "application/json",
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        let chunk = Data(repeating: 0x41, count: 4096)
        let total = SunsetHueConstants.maxResponseBytes + chunk.count * 4
        var sent = 0
        while sent < total {
            if Task.isCancelled {
                Self.cancelCounter.increment()
                client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
                return
            }
            client?.urlProtocol(self, didLoad: chunk)
            sent += chunk.count
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        Self.cancelCounter.increment()
    }
}

final class StreamingTransportTests: XCTestCase {
    override func tearDown() {
        URLProtocol.unregisterClass(OversizedStreamURLProtocol.self)
        OversizedStreamURLProtocol.reset()
        super.tearDown()
    }

    func testStreamingRejectsOversizedBodyWithoutTrustworthyContentLength() async throws {
        OversizedStreamURLProtocol.reset()
        URLProtocol.registerClass(OversizedStreamURLProtocol.self)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OversizedStreamURLProtocol.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionTransport(session: session)

        let url = URL(string: "https://\(OversizedStreamURLProtocol.markerHost)/event")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            _ = try await transport.perform(request)
            XCTFail("Expected oversizedResponse")
        } catch let error as SunsetHueError {
            XCTAssertEqual(error, .oversizedResponse)
        } catch {
            XCTFail("Unexpected \(error)")
        }

        XCTAssertGreaterThan(OversizedStreamURLProtocol.cancelCount, 0)
    }

    func testStreamingRejectsOversizedContentLengthBeforeBody() async {
        final class ContentLengthURLProtocol: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool {
                request.url?.host == "content-length.sunsethue.test"
            }

            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

            override func startLoading() {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(SunsetHueConstants.maxResponseBytes + 1)",
                    ]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                // Body should not be required; transport cancels after headers.
                client?.urlProtocolDidFinishLoading(self)
            }

            override func stopLoading() {}
        }

        URLProtocol.registerClass(ContentLengthURLProtocol.self)
        defer { URLProtocol.unregisterClass(ContentLengthURLProtocol.self) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ContentLengthURLProtocol.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionTransport(session: session)
        var request = URLRequest(url: URL(string: "https://content-length.sunsethue.test/event")!)
        request.httpMethod = "GET"

        do {
            _ = try await transport.perform(request)
            XCTFail("Expected oversizedResponse")
        } catch let error as SunsetHueError {
            XCTAssertEqual(error, .oversizedResponse)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
}
