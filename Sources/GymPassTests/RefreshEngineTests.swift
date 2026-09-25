import Foundation
import GymPassCore
import GymPassShared

private actor TestSettings {
    var appearance = PassAppearance(title: "GymPass", gymLabel: "Bagshot", memberName: "Jack")
    var location: PassLocation? = PassLocation(label: "Bagshot", latitude: 51.3432, longitude: -0.6987)
    var webServiceURL: String? = "https://wallet.example.com"
    var policy = RefreshPolicy(mode: .balanced, floorIntervalSeconds: 300)
    var expirationDate: Date?

    func setBackground(_ hex: String) { appearance.backgroundHex = hex }
}

private struct Stack {
    let db: DatabaseManager
    let walletService: WalletService
    let puregym: MockPureGymClient
    let apns: MockAPNsClient
    let engine: RefreshEngine
    let settings: TestSettings
}

private func makeStack() async throws -> Stack {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("gympass-refresh-\(UUID().uuidString).sqlite").path
    let db = try DatabaseManager(path: path)
    try await db.migrate()
    let crypto = CryptoBox(key: CryptoBox.randomKey())
    let secrets = InMemorySecretStore()
    let walletService = WalletService(db: db, secrets: secrets, crypto: crypto)
    try await walletService.setPassIdentity(passTypeIdentifier: "pass.com.jackwells.gympass.test", serialNumber: "SERIAL-1", teamIdentifier: "TESTTEAM123")

    let box = try PassSigner.inMemoryIdentity(p12: TestSupport.identityData(), password: "gympass-test")
    let passService = WalletPassService(signer: PassSigner(identity: box))

    let puregym = MockPureGymClient(changeEverySeconds: 3600, validitySeconds: 7 * 24 * 3600)
    _ = try await puregym.authenticate(email: "demo@example.com", pin: "00000000")
    let apns = MockAPNsClient()
    let activity = ActivityRecorder(db: db)
    let dispatcher = NotificationDispatcher(db: db, apns: apns, activity: activity) { passType in
        WalletAPNsPolicy(topic: passType)
    }
    let settings = TestSettings()

    let context = RefreshContext(
        passIdentity: {
            PassIdentity(passTypeIdentifier: "pass.com.jackwells.gympass.test", serialNumber: "SERIAL-1", teamIdentifier: "TESTTEAM123")
        },
        appearance: { await settings.appearance },
        location: { await settings.location },
        webServiceURL: { await settings.webServiceURL },
        passToken: { serial in try? await walletService.ensurePassToken(serialNumber: serial) },
        policy: { await settings.policy },
        expirationDate: { await settings.expirationDate }
    )

    let engine = RefreshEngine(
        puregym: puregym,
        db: db,
        crypto: crypto,
        passService: passService,
        walletService: walletService,
        dispatcher: dispatcher,
        activity: activity,
        context: context
    )
    return Stack(db: db, walletService: walletService, puregym: puregym, apns: apns, engine: engine, settings: settings)
}

func refreshEngineTestCases() -> [TestCase] {
    [
        TestCase("refresh.publishesNewPass") { context in
            let stack = try await makeStack()
            let outcome = await stack.engine.refresh(trigger: .manual)
            context.expectEqual(outcome, .changed(revision: 1))
            let state = try await stack.db.passState(serialNumber: "SERIAL-1")
            context.expectEqual(state?.revision, 1)
            context.expectNotNil(try await stack.db.qrState()?.qrHash)
            let published = try await stack.walletService.publishedPass(serialNumber: "SERIAL-1")
            context.expectNotNil(published)
            if let published {
                _ = try PassVerifier.verify(archive: published.archive)
            }
        },
        TestCase("refresh.unchangedWhenCodeIsStable") { context in
            let stack = try await makeStack()
            _ = await stack.engine.refresh(trigger: .manual)
            let second = await stack.engine.refresh(trigger: .scheduled)
            context.expectEqual(second, .unchanged)
            context.expectEqual(try await stack.db.passState(serialNumber: "SERIAL-1")?.revision, 1)
        },
        TestCase("refresh.republishesOnAppearanceChange") { context in
            let stack = try await makeStack()
            _ = await stack.engine.refresh(trigger: .manual)
            await stack.settings.setBackground("#000000")
            let outcome = await stack.engine.refresh(trigger: .manual)
            context.expectEqual(outcome, .changed(revision: 2))
            context.expectEqual(try await stack.db.passState(serialNumber: "SERIAL-1")?.revision, 2)
        },
        TestCase("refresh.failurePreservesLastPublishedPass") { context in
            let stack = try await makeStack()
            _ = await stack.engine.refresh(trigger: .manual)
            await stack.puregym.setFailureMode(.serverError)
            let outcome = await stack.engine.refresh(trigger: .manual)
            context.expect(outcome.isFailure, "expected a failure outcome, got \(outcome)")
            context.expectEqual(try await stack.db.passState(serialNumber: "SERIAL-1")?.revision, 1)
            let published = try await stack.walletService.publishedPass(serialNumber: "SERIAL-1")
            context.expectNotNil(published, "last known-good pass must be preserved")
        },
        TestCase("refresh.authenticationFailureIsReported") { context in
            let stack = try await makeStack()
            await stack.puregym.setFailureMode(.unauthorized)
            let outcome = await stack.engine.refresh(trigger: .manual)
            context.expectEqual(outcome, .failed("authentication_required"))
        },
        TestCase("refresh.notifiesRegisteredDevices") { context in
            let stack = try await makeStack()
            _ = try await stack.db.upsertRegistration(deviceLibraryIdentifier: "DEV-1", passTypeIdentifier: "pass.com.jackwells.gympass.test", serialNumber: "SERIAL-1", pushToken: Data([0xAB, 0xCD]))
            _ = await stack.engine.refresh(trigger: .manual)
            await stack.settings.setBackground("#111111")
            _ = await stack.engine.refresh(trigger: .manual)
            let sent = await stack.apns.sentCount
            context.expect(sent >= 1, "expected at least one APNs notification, got \(sent)")
            context.expectEqual(try await stack.db.pendingOutboxCount(), 0)
        },
    ]
}
