import Foundation
import Security

public protocol CredentialStore: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

/// App-only Keychain store. The widget never reads credentials.
///
/// Prefer the Data Protection Keychain when the process has the required
/// entitlements (signed builds). Fall back to the traditional login Keychain
/// when Data Protection returns entitlement/owner errors (typical for unsigned
/// GitHub Release DMGs). Both backends remain Keychain storage — never plaintext.
public struct KeychainCredentialStore: CredentialStore {
    private enum Backend: CaseIterable {
        case dataProtection
        case login

        var usesDataProtection: Bool {
            switch self {
            case .dataProtection: return true
            case .login: return false
            }
        }
    }

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
        var lastError: SunsetHueError?
        for backend in Backend.allCases {
            do {
                if let key = try loadAPIKey(backend: backend) {
                    return key
                }
            } catch let error as SunsetHueError {
                if Self.shouldTryFallback(error) {
                    lastError = error
                    continue
                }
                throw error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SunsetHueError.missingCredentials
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw SunsetHueError.missingCredentials
        }

        var lastError: SunsetHueError?
        for backend in Backend.allCases {
            do {
                try upsertAPIKey(data: data, backend: backend)
                // Remove a stale copy from the other backend so load is unambiguous.
                try? deleteAPIKey(backend: backend == .dataProtection ? .login : .dataProtection)
                return
            } catch let error as SunsetHueError {
                if Self.shouldTryFallback(error) {
                    lastError = error
                    continue
                }
                throw error
            }
        }
        throw lastError ?? .keychainUnavailable
    }

    public func deleteAPIKey() throws {
        var lastError: SunsetHueError?
        var deletedAny = false
        for backend in Backend.allCases {
            do {
                try deleteAPIKey(backend: backend)
                deletedAny = true
            } catch let error as SunsetHueError {
                if Self.shouldTryFallback(error) {
                    lastError = error
                    continue
                }
                throw error
            }
        }
        if !deletedAny, let lastError {
            throw lastError
        }
    }

    // MARK: - Backend operations

    private func loadAPIKey(backend: Backend) throws -> String? {
        var query = baseQuery(backend: backend)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStatusMapper.error(for: status)
        }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func upsertAPIKey(data: Data, backend: Backend) throws {
        let query = baseQuery(backend: backend)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: "SunsetHue API Key",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainStatusMapper.error(for: updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrLabel as String] = "SunsetHue API Key"
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStatusMapper.error(for: addStatus)
        }
    }

    private func deleteAPIKey(backend: Backend) throws {
        let status = SecItemDelete(baseQuery(backend: backend) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw KeychainStatusMapper.error(for: status)
    }

    private func baseQuery(backend: Backend) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if backend.usesDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private static func shouldTryFallback(_ error: SunsetHueError) -> Bool {
        error == .keychainEntitlementMisconfigured
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
