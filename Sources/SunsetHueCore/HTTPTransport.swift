import Foundation

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public func headerValue(forName name: String) -> String? {
        if let exact = headers[name] { return exact }
        let lowered = name.lowercased()
        return headers.first(where: { $0.key.lowercased() == lowered })?.value
    }
}

public protocol HTTPTransport: Sendable {
    func perform(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeNonRedirectingSession()) {
        self.session = session
    }

    public static func makeSession(
        timeout: TimeInterval = SunsetHueConstants.apiTimeoutSeconds
    ) -> URLSession {
        makeNonRedirectingSession(timeout: timeout)
    }

    public func perform(_ request: URLRequest) async throws -> HTTPResponse {
        guard let url = request.url, url.scheme?.lowercased() == "https" else {
            throw SunsetHueError.invalidRequest
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw SunsetHueError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw SunsetHueError.networkUnavailable
            default:
                throw SunsetHueError.networkUnavailable
            }
        } catch {
            throw SunsetHueError.networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw SunsetHueError.invalidResponse("non_http_response")
        }

        if let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
           let length = Int(contentLength),
           length > SunsetHueConstants.maxResponseBytes {
            throw SunsetHueError.oversizedResponse
        }
        if data.count > SunsetHueConstants.maxResponseBytes {
            throw SunsetHueError.oversizedResponse
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }

        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

/// Injectable transport for tests.
public final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    public struct Stub: Sendable {
        public let statusCode: Int
        public let headers: [String: String]
        public let body: Data
        public let error: SunsetHueError?

        public init(
            statusCode: Int = 200,
            headers: [String: String] = [:],
            body: Data = Data(),
            error: SunsetHueError? = nil
        ) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.error = error
        }
    }

    private let queue = DispatchQueue(label: "MockHTTPTransport")
    private var stubs: [Stub]
    private var _requests: [URLRequest] = []

    public var requests: [URLRequest] {
        queue.sync { _requests }
    }

    public init(stubs: [Stub] = []) {
        self.stubs = stubs
    }

    public func enqueue(_ stub: Stub) {
        queue.sync { stubs.append(stub) }
    }

    public func perform(_ request: URLRequest) async throws -> HTTPResponse {
        let stub: Stub = try queue.sync {
            _requests.append(request)
            guard !stubs.isEmpty else {
                throw SunsetHueError.networkUnavailable
            }
            // Prefer a stub whose JSON `data.type` matches the request `type` query
            // so concurrent forecast fetches do not race on FIFO order.
            if let requestedType = URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "type" })?
                .value,
               let index = stubs.firstIndex(where: { stubMatchesEventType($0, requestedType) }) {
                return stubs.remove(at: index)
            }
            return stubs.removeFirst()
        }

        if let error = stub.error {
            throw error
        }
        if stub.body.count > SunsetHueConstants.maxResponseBytes {
            throw SunsetHueError.oversizedResponse
        }
        return HTTPResponse(statusCode: stub.statusCode, headers: stub.headers, body: stub.body)
    }

    private func stubMatchesEventType(_ stub: Stub, _ requestedType: String) -> Bool {
        guard stub.error == nil,
              let payload = try? JSONSerialization.jsonObject(with: stub.body) as? [String: Any],
              let data = payload["data"] as? [String: Any],
              let type = data["type"] as? String else {
            return false
        }
        return type == requestedType
    }
}
