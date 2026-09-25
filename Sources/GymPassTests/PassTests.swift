import Foundation
import GymPassCore
import GymPassShared

private func sampleInputs(qr: String = "exerp:checkin:one-two-three") -> PassBuildInputs {
    PassBuildInputs(
        passTypeIdentifier: "pass.com.jackwells.gympass.test",
        teamIdentifier: "TESTTEAM123",
        serialNumber: "SERIAL-1",
        authenticationToken: "auth-token-value",
        webServiceURL: "https://wallet.example.com",
        qrPayload: qr,
        appearance: PassAppearance(title: "GymPass", gymLabel: "Bagshot", memberName: "Jack"),
        location: PassLocation(label: "Bagshot", latitude: 51.3432, longitude: -0.6987)
    )
}

private func makeSignedService() throws -> WalletPassService {
    let box = try PassSigner.inMemoryIdentity(p12: TestSupport.identityData(), password: "gympass-test")
    return WalletPassService(signer: PassSigner(identity: box))
}

func passTestCases() -> [TestCase] {
    [
        TestCase("pass.documentFieldsAndVerbatimQR") { context in
            let document = PassBuilder.document(sampleInputs())
            context.expectEqual(document.formatVersion, 1)
            context.expectEqual(document.passTypeIdentifier, "pass.com.jackwells.gympass.test")
            context.expectEqual(document.serialNumber, "SERIAL-1")
            context.expectEqual(document.teamIdentifier, "TESTTEAM123")
            context.expectEqual(document.webServiceURL, "https://wallet.example.com")
            context.expectEqual(document.authenticationToken, "auth-token-value")
            context.expectEqual(document.barcodes.first?.format, "PKBarcodeFormatQR")
            context.expectEqual(document.barcodes.first?.message, "exerp:checkin:one-two-three")
            context.expectEqual(document.barcodes.first?.messageEncoding, "iso-8859-1")
            context.expectEqual(document.locations?.first?.latitude, 51.3432)
            context.expectEqual(document.sharingProhibited, true)

            let encoded = try PassBuilder.encode(document)
            let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            let barcodes = object?["barcodes"] as? [[String: Any]]
            context.expectEqual(barcodes?.first?["message"] as? String, "exerp:checkin:one-two-three")
            context.expectNil(object?["voided"])
        },
        TestCase("pass.manifestIsSHA1") { context in
            let manifest = try PassManifest.data(files: ["a.txt": Data("a".utf8)])
            let decoded = try PassManifest.decode(manifest)
            context.expectEqual(decoded["a.txt"], "86f7e437faa5a7fce15d1ddcb9eaeaea377667b8")
        },
        TestCase("pass.zipFilesAtRoot") { context in
            let archive = try ZipArchiver.zip(files: ["pass.json": Data("{}".utf8), "icon.png": Data([0x89, 0x50])])
            let names = try ZipArchiver.entryNames(archive)
            context.expectEqual(names, ["icon.png", "pass.json"])
            context.expectEqual(try ZipArchiver.unzip(archive)["pass.json"], Data("{}".utf8))
        },
        TestCase("pass.contentIdentitySensitiveToChanges") { context in
            var changed = sampleInputs()
            changed.appearance.backgroundHex = "#000000"
            context.expectNotEqual(WalletPassService.contentIdentity(for: sampleInputs()), WalletPassService.contentIdentity(for: changed))
            var changedQR = sampleInputs()
            changedQR.qrPayload = "exerp:checkin:different"
            context.expectNotEqual(WalletPassService.contentIdentity(for: sampleInputs()), WalletPassService.contentIdentity(for: changedQR))
        },
        TestCase("pass.generatedAssetsArePNGs") { context in
            let assets = PassAssetRenderer.assets(appearance: .default)
            for name in ["icon.png", "icon@2x.png", "logo.png", "thumbnail.png"] {
                guard let data = assets[name] else {
                    context.expect(false, "missing asset \(name)")
                    continue
                }
                context.expectEqual(Data(data.prefix(4)), Data([0x89, 0x50, 0x4E, 0x47]), "\(name) is not a PNG")
            }
        },
        TestCase("signing.selfTest") { context in
            let box = try PassSigner.inMemoryIdentity(p12: TestSupport.identityData(), password: "gympass-test")
            let signer = PassSigner(identity: box)
            let result = await signer.selfTest()
            context.expect(result.passed, result.detail)
        },
        TestCase("signing.archiveVerifies") { context in
            let service = try makeSignedService()
            let generated = try await service.generate(inputs: sampleInputs())
            let files = try ZipArchiver.unzip(generated.archive)
            context.expectNotNil(files["pass.json"])
            context.expectNotNil(files["manifest.json"])
            context.expectNotNil(files["signature"])
            context.expectNotNil(files["icon.png"])
            let verification = try PassVerifier.verify(archive: generated.archive)
            context.expectEqual(verification.signerStatus, "valid")
            context.expectEqual(verification.fileCount, files.count)
            context.expect(!generated.contentIdentity.isEmpty, "content identity must not be empty")
        },
        TestCase("signing.tamperedAssetRejected") { context in
            let service = try makeSignedService()
            let generated = try await service.generate(inputs: sampleInputs())
            var files = try ZipArchiver.unzip(generated.archive)
            files["pass.json"] = Data("{\"formatVersion\":1}".utf8)
            let tampered = try ZipArchiver.zip(files: files)
            context.expectThrows("tampered archive must fail verification") {
                _ = try PassVerifier.verify(archive: tampered)
            }
        },
        TestCase("signing.manifestMismatchRejected") { context in
            let service = try makeSignedService()
            let generated = try await service.generate(inputs: sampleInputs())
            var files = try ZipArchiver.unzip(generated.archive)
            files["manifest.json"] = try PassManifest.data(files: ["pass.json": Data("different".utf8)])
            let broken = try ZipArchiver.zip(files: files)
            context.expectThrows("manifest mismatch must fail verification") {
                _ = try PassVerifier.verify(archive: broken)
            }
        },
    ]
}
