import Foundation
import Security

public protocol CredentialStore: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

/// App-only Keychain store. The widget never reads credentials.
///
/// Uses the data-protection keychain without a custom access group.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account: String

    public init(
        service: String = SunsetHueConstants.keychainService,
        account: String = SunsetHueConstants.keychainAccount
    ) {
        self.service = service
        self.account = account
    }

    public func loadAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        if status == errSecInteractionNotAllowed {
            throw SunsetHueError.keychainUnavailable
        }
        guard status == errSecSuccess else {
            throw mapKeychainStatus(status)
        }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SunsetHueError.missingCredentials
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw SunsetHueError.missingCredentials
        }

        try deleteAPIKey()

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = "SunsetHue API Key"
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw mapKeychainStatus(status)
        }
    }

    public func deleteAPIKey() throws {
        _ = SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func mapKeychainStatus(_ status: OSStatus) -> SunsetHueError {
        switch status {
        case errSecInteractionNotAllowed:
            return .keychainUnavailable
        case errSecItemNotFound:
            return .missingCredentials
        default:
            return .keychainUnavailable
        }
    }
}

/// Maps Keychain OSStatus values for unit tests without touching the real keychain.
public enum KeychainStatusMapper {
    public static func error(for status: OSStatus) -> SunsetHueError {
        switch status {
        case errSecInteractionNotAllowed:
            return .keychainUnavailable
        case errSecItemNotFound:
            return .missingCredentials
        case errSecMissingEntitlement, errSecInvalidOwnerEdit:
            return .keychainEntitlementMisconfigured
        default:
            return .keychainUnavailable
        }
    }
}

/// Thread-safe in-memory credentials for tests and SwiftUI previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var apiKey: String?

    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    public func loadAPIKey() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return apiKey
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SunsetHueError.missingCredentials }
        lock.lock(); defer { lock.unlock() }
        self.apiKey = trimmed
    }

    public func deleteAPIKey() throws {
        lock.lock(); defer { lock.unlock() }
        self.apiKey = nil
    }
}
