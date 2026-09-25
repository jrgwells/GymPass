import Foundation
import GymPassShared

public struct GeneratedPass: Sendable {
    public var archive: Data
    /// Stable identity of the meaningful pass content. Used for change detection.
    public var contentIdentity: String
    /// SHA-256 of the produced archive bytes (diagnostics only; archives are not byte-stable).
    public var archiveHash: String
    public var serialNumber: String
    public var passTypeIdentifier: String
    public var fileNames: [String]
}

public actor WalletPassService {
    private let signer: PassSigner

    public init(signer: PassSigner) {
        self.signer = signer
    }

    public func generate(inputs: PassBuildInputs) async throws -> GeneratedPass {
        let document = PassBuilder.document(inputs)
        let passJSON = try PassBuilder.encode(document)
        let assets = PassAssetRenderer.assets(appearance: inputs.appearance)

        var files = assets
        files["pass.json"] = passJSON

        let manifestData = try PassManifest.data(files: files)
        let signature = try await signer.signDetached(manifest: manifestData)

        var archiveFiles = files
        archiveFiles["manifest.json"] = manifestData
        archiveFiles["signature"] = signature

        let archive = try ZipArchiver.zip(files: archiveFiles)
        _ = try PassVerifier.verify(archive: archive)

        return GeneratedPass(
            archive: archive,
            contentIdentity: Self.contentIdentity(for: inputs),
            archiveHash: ArchiveContentHash.sha256(archive),
            serialNumber: inputs.serialNumber,
            passTypeIdentifier: inputs.passTypeIdentifier,
            fileNames: archiveFiles.keys.sorted()
        )
    }

    /// Canonical identity of everything that should trigger a new revision.
    public static func contentIdentity(for inputs: PassBuildInputs) -> String {
        var components: [String] = [
            "v1",
            inputs.passTypeIdentifier,
            inputs.teamIdentifier,
            inputs.serialNumber,
            inputs.qrPayload,
            inputs.webServiceURL ?? "",
            inputs.appearance.title,
            inputs.appearance.gymLabel,
            inputs.appearance.memberName ?? "",
            inputs.appearance.showMemberName ? "1" : "0",
            inputs.appearance.foregroundHex,
            inputs.appearance.backgroundHex,
            inputs.appearance.labelHex,
            inputs.appearance.logoFileName ?? "",
        ]
        if let location = inputs.location {
            components.append("loc:\(location.label):\(location.latitude):\(location.longitude):\(location.relevantText ?? "")")
        }
        if let expiry = inputs.expirationDate {
            components.append("exp:\(Int(expiry.timeIntervalSince1970))")
        }
        return ArchiveContentHash.sha256(components.joined(separator: "|"))
    }
}
