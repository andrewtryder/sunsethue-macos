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
    case keychainUnavailable
    case keychainEntitlementMisconfigured
    case invalidCoordinates
    case invalidLocation(String)
    case duplicateLocation
    case unexpectedStatus(Int)
    case storageCorrupt
    case storageTooLarge

    public var isTransient: Bool {
        switch self {
        case .networkUnavailable, .timeout, .serviceUnavailable, .rateLimited, .unexpectedStatus:
            true
        case .authentication, .invalidRequest, .oversizedResponse, .invalidJSON,
             .invalidResponse, .missingCredentials, .keychainUnavailable,
             .keychainEntitlementMisconfigured, .invalidCoordinates,
             .invalidLocation, .duplicateLocation, .storageCorrupt, .storageTooLarge:
            false
        }
    }

    public var isAuthenticationFailure: Bool {
        self == .authentication || self == .missingCredentials
    }

    /// User-facing message. Never includes credentials or request headers.
    public var userMessage: String {
        switch self {
        case .authentication:
            "Authentication failed. Open SunsetHue to update your API key."
        case .invalidRequest, .invalidCoordinates:
            "The request or coordinates were rejected. Check latitude and longitude."
        case .rateLimited:
            "Rate limited by SunsetHue. Try again later."
        case .networkUnavailable:
            "Network unavailable. Showing the last saved forecast if available."
        case .timeout:
            "The request timed out. Try again shortly."
        case .serviceUnavailable, .unexpectedStatus:
            "SunsetHue is temporarily unavailable."
        case .oversizedResponse:
            "The server response was unexpectedly large."
        case .invalidJSON, .invalidResponse:
            "Received an invalid response from SunsetHue."
        case .missingCredentials:
            "Add your SunsetHue API key in the app."
        case .keychainUnavailable:
            "Keychain is unavailable. Unlock your Mac and try again."
        case .keychainEntitlementMisconfigured:
            "Secure storage could not use the Data Protection Keychain for this build."
        case let .invalidLocation(message):
            message
        case .duplicateLocation:
            "A location with these coordinates already exists."
        case .storageCorrupt:
            "Saved data was damaged and was reset."
        case .storageTooLarge:
            "Saved data exceeded the allowed size and was ignored."
        }
    }

    /// Technical diagnostics without secrets.
    public var diagnosticDescription: String {
        switch self {
        case .authentication: "auth_failed"
        case .invalidRequest: "invalid_request"
        case let .rateLimited(retry): "rate_limited retry_after=\(retry.map(String.init) ?? "nil")"
        case .networkUnavailable: "network_unavailable"
        case .timeout: "timeout"
        case .serviceUnavailable: "service_unavailable"
        case .oversizedResponse: "oversized_response"
        case .invalidJSON: "invalid_json"
        case let .invalidResponse(detail): "invalid_response:\(detail)"
        case .missingCredentials: "missing_credentials"
        case .keychainUnavailable: "keychain_unavailable"
        case .keychainEntitlementMisconfigured: "keychain_entitlement_misconfigured"
        case .invalidCoordinates: "invalid_coordinates"
        case let .invalidLocation(detail): "invalid_location:\(detail)"
        case .duplicateLocation: "duplicate_location"
        case let .unexpectedStatus(code): "unexpected_status:\(code)"
        case .storageCorrupt: "storage_corrupt"
        case .storageTooLarge: "storage_too_large"
        }
    }
}
