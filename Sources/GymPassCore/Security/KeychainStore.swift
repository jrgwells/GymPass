import Foundation
import GymPassShared
import Security

/// Actor-backed wrapper around the macOS Keychain. The agent is the only
/// process that touches these items.
public actor KeychainStore {
    public static let service = "com.jackwells.gympass"

    public enum Key: String {
        case puregymEmail = "puregym.email"
        case puregymPIN = "puregym.pin"
        case puregymTokens = "puregym.tokens"
        case dataKey = "datakey"
        case tunnelCredentials = "tunnel.credentials"
        case signingFingerprint = "signing.identity.fingerprint"
        case signingPassType = "signing.identity.passtype"
        case signingTeam = "signing.identity.team"
        case signingExpiry = "signing.identity.expiry"

        func passToken(serial: String) -> String { "wallet.passtoken.\(serial)" }
        func installToken(id: String) -> String { "install.token.\(id)" }
    }

    public enum DynamicKey {
        public static func passToken(serial: String) -> String { "wallet.passtoken.\(serial)" }
        public static func installToken(id: String) -> String { "install.token.\(id)" }
    }

    public init() {}

    public func set(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw GymPassError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw GymPassError.keychain(status)
        }
    }

    public func set(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw GymPassError.crypto("Could not encode secret as UTF-8")
        }
        try set(data, for: key)
    }

    public func get(_ key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GymPassError.keychain(status) }
        return result as? Data
    }

    public func getString(_ key: String) throws -> String? {
        guard let data = try get(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GymPassError.keychain(status)
        }
    }

    public func exists(_ key: String) -> Bool {
        (try? get(key)) != nil
    }
}
