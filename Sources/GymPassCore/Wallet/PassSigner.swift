import Foundation
import Security
import GymPassShared

/// Produces the detached PKCS#7 signature Wallet requires. Signing algorithm is
/// SHA-256; the manifest file hashes remain SHA-1 as defined by the Wallet
/// format.
public actor PassSigner {
    private let identityProvider: @Sendable () async throws -> IdentityBox?

    public init(signingStore: SigningIdentityStore) {
        self.identityProvider = { try await signingStore.loadIdentity() }
    }

    public init(identity: IdentityBox) {
        self.identityProvider = { identity }
    }

    public func signDetached(manifest: Data) async throws -> Data {
        guard let box = try await identityProvider() else {
            throw GymPassError.signingUnavailable("No Wallet signing certificate has been imported.")
        }
        return try Self.signDetached(manifest: manifest, identity: box.identity)
    }

    /// Runs a signing self-test against a small fixed payload.
    public func selfTest() async -> (passed: Bool, detail: String) {
        do {
            let payload = Data("GymPass signing self-test".utf8)
            let signature = try await signDetached(manifest: payload)
            let verification = try PassVerifier.verifyCMS(signature: signature, detachedContent: payload)
            switch verification {
            case .valid(let name):
                return (true, name.map { "Signed and verified as \($0)" } ?? "Signed and verified")
            case .invalid(let reason):
                return (false, reason)
            }
        } catch {
            return (false, (error as? GymPassError)?.userMessage ?? "Signing failed.")
        }
    }

    // MARK: - Core CMS signing

    public static func signDetached(manifest: Data, identity: SecIdentity) throws -> Data {
        var encoderRef: CMSEncoder?
        var status = CMSEncoderCreate(&encoderRef)
        guard status == errSecSuccess, let encoder = encoderRef else {
            throw GymPassError.signingFailed("Could not create CMS encoder (OSStatus \(status)).")
        }

        status = CMSEncoderSetSignerAlgorithm(encoder, kCMSEncoderDigestAlgorithmSHA256)
        guard status == errSecSuccess else {
            throw GymPassError.signingFailed("Could not select signing algorithm (OSStatus \(status)).")
        }

        status = CMSEncoderAddSigners(encoder, identity)
        guard status == errSecSuccess else {
            throw GymPassError.signingFailed("Could not add signing identity (OSStatus \(status)).")
        }

        status = CMSEncoderSetHasDetachedContent(encoder, true)
        guard status == errSecSuccess else {
            throw GymPassError.signingFailed("Could not mark signature detached (OSStatus \(status)).")
        }

        status = manifest.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return CMSEncoderUpdateContent(encoder, base, manifest.count)
        }
        guard status == errSecSuccess else {
            throw GymPassError.signingFailed("Could not feed manifest to signer (OSStatus \(status)).")
        }

        var encoded: CFData?
        status = CMSEncoderCopyEncodedContent(encoder, &encoded)
        guard status == errSecSuccess, let encoded else {
            throw GymPassError.signingFailed("Could not produce signature (OSStatus \(status)).")
        }
        return encoded as Data
    }

    /// Imports a PKCS#12 blob into memory only (no keychain writes). Intended
    /// for tests and signing self-tests against an imported identity.
    public static func inMemoryIdentity(p12: Data, password: String) throws -> IdentityBox {
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password,
            kSecImportToMemoryOnly as String: true,
        ]
        var items: CFArray?
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess else {
            throw GymPassError.signingFailed("The certificate could not be imported (OSStatus \(status)).")
        }
        guard let array = items as? [[String: Any]],
              let first = array.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            throw GymPassError.signingFailed("The imported file did not contain a usable identity.")
        }
        return IdentityBox(unsafeBitCast(identityRef, to: SecIdentity.self))
    }
}
