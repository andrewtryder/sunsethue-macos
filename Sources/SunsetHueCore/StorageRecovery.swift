import Foundation

public struct StorageRecovery: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case corrupt
        case tooLarge
        case unsupportedSchema
    }

    public let quarantineFileName: String
    public let reason: Reason

    public init(quarantineFileName: String, reason: Reason) {
        self.quarantineFileName = quarantineFileName
        self.reason = reason
    }

    public var userMessage: String {
        "Saved settings were damaged. The original file was preserved as \(quarantineFileName)."
    }
}

public struct StoreLoadResult<Value: Sendable>: Sendable {
    public let value: Value
    public let recovery: StorageRecovery?

    public init(value: Value, recovery: StorageRecovery? = nil) {
        self.value = value
        self.recovery = recovery
    }
}

public enum CredentialState: Equatable, Sendable {
    case unknown
    case configured
    case missing
    case unavailable
}
