import Foundation

public protocol CurrentLocationProviding: AnyObject, Sendable {
    func requestLocation() async throws -> CurrentLocationResult
}

public struct CurrentLocationResult: Sendable {
    public let latitude: Double
    public let longitude: Double
    /// Geographic IANA identifier when reverse-geocoding succeeds; otherwise nil.
    public let timeZoneIdentifier: String?

    public init(latitude: Double, longitude: Double, timeZoneIdentifier: String?) {
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

#if DEBUG
    /// Test double that counts invocations.
    /// Safe `@unchecked Sendable` invariant: all mutable state (`_requestCount`, `_result`)
    /// is exclusively accessed while holding `lock`.
    public final class CountingLocationProvider: CurrentLocationProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var _requestCount = 0
        private var _result = CurrentLocationResult(
            latitude: 40.0,
            longitude: -74.0,
            timeZoneIdentifier: "America/New_York"
        )

        public var requestCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _requestCount
        }

        public var result: CurrentLocationResult {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _result
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _result = newValue
            }
        }

        public init() {}

        public func requestLocation() async throws -> CurrentLocationResult {
            consumeRequest()
        }

        private func consumeRequest() -> CurrentLocationResult {
            lock.lock()
            defer { lock.unlock() }
            _requestCount += 1
            return _result
        }
    }
#endif
