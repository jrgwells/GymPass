import Foundation
import GymPassShared
import Security
import CryptoKit

/// Wrapper so a `SecIdentity` can cross concurrency boundaries. The identity is
/// an immutable handle to keychain material; all use is serialised by the
/// `SigningIdentityStore` actor and the `PassSigner` actor.
public struct IdentityBox: @unchecked Sendable {
    public let identity: SecIdentity
    public init(_ identity: SecIdentity) { self.identity = identity }
}

public struct SigningIdentityInfo: Sendable, Equatable {
    public var passTypeIdentifier: String?
    public var teamIdentifier: String?
    public var commonName: String?
    public var organization: String?
    public var expiresAt: Date?
    public var fingerprint: String
    public var hasPrivateKey: Bool

    public init(passTypeIdentifier: String?, teamIdentifier: String?, commonName: String?, organization: String?, expiresAt: Date?, fingerprint: String, hasPrivateKey: Bool) {
        self.passTypeIdentifier = passTypeIdentifier
        self.teamIdentifier = teamIdentifier
        self.commonName = commonName
        self.organization = organization
        self.expiresAt = expiresAt
        self.fingerprint = fingerprint
        self.hasPrivateKey = hasPrivateKey
    }

    public var kind: SigningStatus.Kind {
        guard hasPrivateKey else { return .missingPrivateKey }
        guard let expiresAt else { return .notConfigured }
        if expiresAt < Date() { return .expired }
        if expiresAt < Date().addingTimeInterval(60 * 60 * 24 * 30) { return .expiringSoon }
        return .valid
    }
}

public enum CertificateInspector {
    public static func details(of certificate: SecCertificate) -> (commonName: String?, organization: String?, passTypeIdentifier: String?, teamIdentifier: String?, expiresAt: Date?) {
        var map: [String: String] = [:]
        if let values = SecCertificateCopyValues(certificate, [kSecOIDX509V1SubjectName] as CFArray, nil) as? [CFString: Any],
           let subject = values[kSecOIDX509V1SubjectName] as? [CFString: Any],
           let entries = subject[kSecPropertyKeyValue] as? [[CFString: Any]] {
            for entry in entries {
                guard let label = entry[kSecPropertyKeyLabel] as? String else { continue }
                let value = (entry[kSecPropertyKeyValue] as? String) ?? ""
                map[label] = value
            }
        }

        let commonName = map["CN"] ?? map["2.5.4.3"]
        let organization = map["O"] ?? map["2.5.4.10"]
        let passType = map["UID"] ?? map["0.9.2342.19200300.100.1.1"]
        let team = map["OU"] ?? map["2.5.4.11"]

        var expiresAt: Date?
        if let values = SecCertificateCopyValues(certificate, [kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [CFString: Any],
           let notAfter = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
           let date = notAfter[kSecPropertyKeyValue] as? Date {
            expiresAt = date
        }

        return (commonName, organization, passType, team, expiresAt)
    }

    public static func fingerprint(of certificate: SecCertificate) -> String {
        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public actor SigningIdentityStore {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    public func importPKCS12(_ data: Data, password: String) async throws -> SigningIdentityInfo {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess else {
            if status == errSecAuthFailed || status == errSecPkcs12VerifyFailure {
                throw GymPassError.signingFailed("The certificate password was not correct.")
            }
            throw GymPassError.signingFailed("The certificate could not be imported (OSStatus \(status)).")
        }
        guard let array = items as? [[String: Any]],
              let first = array.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            throw GymPassError.signingFailed("The imported file did not contain a usable identity.")
        }
        let identity = unsafeBitCast(identityRef, to: SecIdentity.self)

        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        guard let certificate else {
            throw GymPassError.signingFailed("The identity had no certificate.")
        }

        let details = CertificateInspector.details(of: certificate)
        let fingerprint = CertificateInspector.fingerprint(of: certificate)
        let hasPrivateKey = Self.identityHasPrivateKey(identity)

        try await keychain.set(fingerprint, for: KeychainStore.Key.signingFingerprint.rawValue)
        if let passType = details.passTypeIdentifier {
            try await keychain.set(passType, for: KeychainStore.Key.signingPassType.rawValue)
        }
        if let team = details.teamIdentifier {
            try await keychain.set(team, for: KeychainStore.Key.signingTeam.rawValue)
        }
        if let expiry = details.expiresAt {
            try await keychain.set(GymPassDate.iso8601(expiry), for: KeychainStore.Key.signingExpiry.rawValue)
        }

        return SigningIdentityInfo(
            passTypeIdentifier: details.passTypeIdentifier,
            teamIdentifier: details.teamIdentifier,
            commonName: details.commonName,
            organization: details.organization,
            expiresAt: details.expiresAt,
            fingerprint: fingerprint,
            hasPrivateKey: hasPrivateKey
        )
    }

    public func clear() async throws {
        try? await keychain.delete(KeychainStore.Key.signingFingerprint.rawValue)
        try? await keychain.delete(KeychainStore.Key.signingPassType.rawValue)
        try? await keychain.delete(KeychainStore.Key.signingTeam.rawValue)
        try? await keychain.delete(KeychainStore.Key.signingExpiry.rawValue)
        if let box = try await loadIdentity() {
            var certificate: SecCertificate?
            SecIdentityCopyCertificate(box.identity, &certificate)
            if let certificate {
                SecItemDelete([
                    kSecClass as String: kSecClassCertificate,
                    kSecValueRef as String: certificate,
                ] as CFDictionary)
            }
            var privateKey: SecKey?
            SecIdentityCopyPrivateKey(box.identity, &privateKey)
            if let privateKey {
                SecItemDelete([
                    kSecClass as String: kSecClassKey,
                    kSecValueRef as String: privateKey,
                ] as CFDictionary)
            }
        }
    }

    public func info() async throws -> SigningIdentityInfo? {
        guard let box = try await loadIdentity() else { return nil }
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(box.identity, &certificate)
        guard let certificate else { return nil }
        let details = CertificateInspector.details(of: certificate)
        return SigningIdentityInfo(
            passTypeIdentifier: details.passTypeIdentifier,
            teamIdentifier: details.teamIdentifier,
            commonName: details.commonName,
            organization: details.organization,
            expiresAt: details.expiresAt,
            fingerprint: CertificateInspector.fingerprint(of: certificate),
            hasPrivateKey: Self.identityHasPrivateKey(box.identity)
        )
    }

    public func loadIdentity() async throws -> IdentityBox? {
        guard let fingerprint = try await keychain.getString(KeychainStore.Key.signingFingerprint.rawValue) else {
            return nil
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        guard let identities = result as? [SecIdentity] else { return nil }
        for identity in identities {
            var certificate: SecCertificate?
            SecIdentityCopyCertificate(identity, &certificate)
            guard let certificate else { continue }
            if CertificateInspector.fingerprint(of: certificate) == fingerprint {
                return IdentityBox(identity)
            }
        }
        return nil
    }

    private static func identityHasPrivateKey(_ identity: SecIdentity) -> Bool {
        var key: SecKey?
        return SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess && key != nil
    }
}
