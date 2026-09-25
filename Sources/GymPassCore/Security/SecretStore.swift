import Foundation
import Security
import GymPassShared

/// Abstraction over secret storage. Production uses the Keychain; tests and
/// demo mode use an in-memory implementation.
public protocol SecretStore: Sendable {
    func set(_ data: Data, for key: String) async throws
    func get(_ key: String) async throws -> Data?
    func delete(_ key: String) async throws
}

public extension SecretStore {
    func set(_ string: String, for key: String) async throws {
        try await set(Data(string.utf8), for: key)
    }

    func getString(_ key: String) async throws -> String? {
        guard let data = try await get(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension KeychainStore: SecretStore {}

/// In-memory secret store for tests and demo mode.
public actor InMemorySecretStore: SecretStore {
    private var storage: [String: Data]

    public init(storage: [String: Data] = [:]) {
        self.storage = storage
    }

    public func set(_ data: Data, for key: String) {
        storage[key] = data
    }

    public func get(_ key: String) -> Data? {
        storage[key]
    }

    public func delete(_ key: String) {
        storage.removeValue(forKey: key)
    }
}
