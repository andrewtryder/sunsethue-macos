import Foundation

/// URLSession delegate that refuses redirects.
public final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    public override init() {
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public extension URLSessionTransport {
    static func makeNonRedirectingSession(
        timeout: TimeInterval = SunsetHueConstants.apiTimeoutSeconds
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = false
        return URLSession(
            configuration: configuration,
            delegate: NoRedirectSessionDelegate(),
            delegateQueue: nil
        )
    }
}
