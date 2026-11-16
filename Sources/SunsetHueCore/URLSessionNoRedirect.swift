import Foundation

/// URLSession delegate that refuses redirects.
public final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    override public init() {
        super.init()
    }

    public func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
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
