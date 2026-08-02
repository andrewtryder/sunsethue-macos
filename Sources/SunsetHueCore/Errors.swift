import Foundation

public enum SunsetHueError: Error, Equatable, Sendable {
    case authentication
    case invalidRequest
    case rateLimited(retryAfter: Int?)
    case networkUnavailable
    case timeout
    case serviceUnavailable
    case oversizedResponse
    case invalidJSON
    case invalidResponse(String)
    case missingCredentials
    case invalidCoordinates
    case invalidLocation(String)
    case duplicateLocation
    case unexpectedStatus(Int)

    public var isTransient: Bool {
        switch self {
        case .networkUnavailable, .timeout, .serviceUnavailable, .rateLimited, .unexpectedStatus:
            return true
        case .authentication, .invalidRequest, .oversizedResponse, .invalidJSON,
             .invalidResponse, .missingCredentials, .invalidCoordinates,
             .invalidLocation, .duplicateLocation:
            return false
        }
    }

    public var isAuthenticationFailure: Bool {
        self == .authentication || self == .missingCredentials
    }

    /// User-facing message. Never includes credentials or request headers.
    public var userMessage: String {
        switch self {
        case .authentication:
            return "Authentication failed. Open SunsetHue to update your API key."
        case .invalidRequest, .invalidCoordinates:
            return "The request or coordinates were rejected. Check latitude and longitude."
        case .rateLimited:
            return "Rate limited by SunsetHue. Try again later."
        case .networkUnavailable:
            return "Network unavailable. Showing the last saved forecast if available."
        case .timeout:
            return "The request timed out. Try again shortly."
        case .serviceUnavailable, .unexpectedStatus:
            return "SunsetHue is temporarily unavailable."
        case .oversizedResponse:
            return "The server response was unexpectedly large."
        case .invalidJSON, .invalidResponse:
            return "Received an invalid response from SunsetHue."
        case .missingCredentials:
            return "Add your SunsetHue API key in the app."
        case .invalidLocation(let message):
            return message
        case .duplicateLocation:
            return "A location with these coordinates already exists."
        }
    }

    /// Technical diagnostics without secrets.
    public var diagnosticDescription: String {
        switch self {
        case .authentication: return "auth_failed"
        case .invalidRequest: return "invalid_request"
        case .rateLimited(let retry): return "rate_limited retry_after=\(retry.map(String.init) ?? "nil")"
        case .networkUnavailable: return "network_unavailable"
        case .timeout: return "timeout"
        case .serviceUnavailable: return "service_unavailable"
        case .oversizedResponse: return "oversized_response"
        case .invalidJSON: return "invalid_json"
        case .invalidResponse(let detail): return "invalid_response:\(detail)"
        case .missingCredentials: return "missing_credentials"
        case .invalidCoordinates: return "invalid_coordinates"
        case .invalidLocation(let detail): return "invalid_location:\(detail)"
        case .duplicateLocation: return "duplicate_location"
        case .unexpectedStatus(let code): return "unexpected_status:\(code)"
        }
    }
}
