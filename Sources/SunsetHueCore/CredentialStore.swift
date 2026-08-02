import Foundation
import Security

public protocol CredentialStore: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

/// Keychain store shared between the app and widget when Keychain Sharing is enabled.
///
/// Uses the data-protection keychain (`kSecUseDataProtectionKeychain`) so items are
/// keyed by access group / Team ID instead of a per-binary file-keychain ACL. That
/// prevents login-password prompts when Launch Services opens a different signed
/// copy of the app (for example from a widget deep link).
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
        if let key = try copyMatching(useAccessGroup: true, useDataProtection: true) {
            return key
        }
        // Migrate items saved before data-protection / Keychain Sharing.
        if let sharedLegacy = try copyMatching(useAccessGroup: true, useDataProtection: false) {
            try saveAPIKey(sharedLegacy)
            return sharedLegacy
        }
        if let legacy = try copyMatching(useAccessGroup: false, useDataProtection: false) {
            try saveAPIKey(legacy)
            return legacy
        }
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

        try deleteAPIKey()

        var query = baseQuery(useAccessGroup: true, useDataProtection: true)
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = "SunsetHue API Key"
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        var status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Unsigned / no team builds: store without access group.
            var fallback = baseQuery(useAccessGroup: false, useDataProtection: true)
            fallback[kSecValueData as String] = data
            fallback[kSecAttrLabel as String] = "SunsetHue API Key"
            fallback[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(fallback as CFDictionary, nil)
            if status != errSecSuccess {
                var fileKeychain = baseQuery(useAccessGroup: false, useDataProtection: false)
                fileKeychain[kSecValueData as String] = data
                fileKeychain[kSecAttrLabel as String] = "SunsetHue API Key"
                fileKeychain[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                status = SecItemAdd(fileKeychain as CFDictionary, nil)
            }
        }
        guard status == errSecSuccess else {
            throw SunsetHueError.missingCredentials
        }
    }

    public func deleteAPIKey() throws {
        _ = SecItemDelete(baseQuery(useAccessGroup: true, useDataProtection: true) as CFDictionary)
        _ = SecItemDelete(baseQuery(useAccessGroup: true, useDataProtection: false) as CFDictionary)
        _ = SecItemDelete(baseQuery(useAccessGroup: false, useDataProtection: true) as CFDictionary)
        _ = SecItemDelete(baseQuery(useAccessGroup: false, useDataProtection: false) as CFDictionary)
    }

    private func copyMatching(useAccessGroup: Bool, useDataProtection: Bool) throws -> String? {
        var query = baseQuery(useAccessGroup: useAccessGroup, useDataProtection: useDataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return nil
        }
        // User cancelled a file-keychain ACL prompt — treat as missing for this path.
        if status == errSecUserCanceled {
            return nil
        }
        guard status == errSecSuccess else {
            throw SunsetHueError.missingCredentials
        }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func baseQuery(useAccessGroup: Bool, useDataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        if useAccessGroup, let accessGroup = Self.resolvedAccessGroup() {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public static func resolvedAccessGroup() -> String? {
        guard let teamID = codeSigningTeamIdentifier() else { return nil }
        return "\(teamID).\(SunsetHueConstants.keychainAccessGroup)"
    }

    public static func codeSigningTeamIdentifier() -> String? {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        guard copyStatus == errSecSuccess,
              let dict = info as? [String: Any],
              let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamID.isEmpty else {
            return nil
        }
        return teamID
    }
}

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
