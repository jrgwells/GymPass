import Foundation
import Security
import GymPassShared

public enum PassVerifier {
    public enum SignerVerification: Sendable, Equatable {
        case valid(commonName: String?)
        case invalid(String)
    }

    public struct ArchiveVerification: Sendable, Equatable {
        public var fileCount: Int
        public var signerCommonName: String?
        public var signerStatus: String
    }

    public static func verifyCMS(signature: Data, detachedContent: Data) throws -> SignerVerification {
        var decoderRef: CMSDecoder?
        var status = CMSDecoderCreate(&decoderRef)
        guard status == errSecSuccess, let decoder = decoderRef else {
            return .invalid("Could not create CMS decoder (OSStatus \(status)).")
        }

        status = CMSDecoderSetDetachedContent(decoder, detachedContent as CFData)
        guard status == errSecSuccess else {
            return .invalid("Could not set detached content (OSStatus \(status)).")
        }

        status = signature.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, base, signature.count)
        }
        guard status == errSecSuccess else {
            return .invalid("Signature was malformed (OSStatus \(status)).")
        }

        status = CMSDecoderFinalizeMessage(decoder)
        guard status == errSecSuccess else {
            return .invalid("Could not finalise CMS decoding (OSStatus \(status)).")
        }

        var numSigners: Int = 0
        guard CMSDecoderGetNumSigners(decoder, &numSigners) == errSecSuccess, numSigners > 0 else {
            return .invalid("The archive was not signed.")
        }

        var signerStatus: CMSSignerStatus = .unsigned
        let policy = SecPolicyCreateBasicX509()
        status = CMSDecoderCopySignerStatus(decoder, 0, policy, false, &signerStatus, nil, nil)
        guard status == errSecSuccess else {
            return .invalid("Could not evaluate signer status (OSStatus \(status)).")
        }

        var commonName: String?
        var certificate: SecCertificate?
        if CMSDecoderCopySignerCert(decoder, 0, &certificate) == errSecSuccess, let certificate {
            commonName = CertificateInspector.details(of: certificate).commonName
        }

        switch signerStatus {
        case .valid:
            return .valid(commonName: commonName)
        case .invalidSignature:
            return .invalid("The signature does not match the content.")
        case .invalidCert:
            return .invalid("The signing certificate could not be validated.")
        case .needsDetachedContent:
            return .invalid("Detached content was required but not supplied.")
        default:
            return .invalid("The signature could not be verified.")
        }
    }

    /// Verifies the full archive: structure, manifest hashes and CMS signature.
    public static func verify(archive: Data) throws -> ArchiveVerification {
        let files = try ZipArchiver.unzip(archive)
        guard let passJSON = files["pass.json"] else {
            throw GymPassError.verificationFailed("The archive is missing pass.json.")
        }
        guard let manifestData = files["manifest.json"] else {
            throw GymPassError.verificationFailed("The archive is missing manifest.json.")
        }
        guard let signature = files["signature"] else {
            throw GymPassError.verificationFailed("The archive is missing its signature.")
        }
        _ = try JSONSerialization.jsonObject(with: passJSON)

        let manifest = try PassManifest.decode(manifestData)
        var contentFiles = files
        contentFiles.removeValue(forKey: "manifest.json")
        contentFiles.removeValue(forKey: "signature")
        let recomputed = PassManifest.hashes(files: contentFiles)

        guard recomputed == manifest else {
            throw GymPassError.verificationFailed("The manifest does not match the archive contents.")
        }

        let verification = try verifyCMS(signature: signature, detachedContent: manifestData)
        switch verification {
        case .valid(let commonName):
            return ArchiveVerification(fileCount: files.count, signerCommonName: commonName, signerStatus: "valid")
        case .invalid(let reason):
            throw GymPassError.verificationFailed(reason)
        }
    }
}
