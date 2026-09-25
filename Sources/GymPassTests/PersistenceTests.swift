import Foundation
import GymPassCore
import GymPassShared

private func makeDatabase() throws -> DatabaseManager {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("gympass-test-\(UUID().uuidString).sqlite")
        .path
    return try DatabaseManager(path: path)
}

func persistenceTestCases() -> [TestCase] {
    [
        TestCase("db.registrationCRUD") { context in
            let db = try makeDatabase()
            try await db.migrate()

            let created = try await db.upsertRegistration(deviceLibraryIdentifier: "DEV1", passTypeIdentifier: "pass.test", serialNumber: "S1", pushToken: Data([0xAA, 0xBB]))
            context.expect(created.created, "first registration should be created")

            let updated = try await db.upsertRegistration(deviceLibraryIdentifier: "DEV1", passTypeIdentifier: "pass.test", serialNumber: "S1", pushToken: Data([0xCC, 0xDD]))
            context.expect(!updated.created, "second registration should update")
            context.expectEqual(updated.tokenGeneration, 2)
            context.expectEqual(try await db.registrationCount(), 1)

            let fetched = try await db.registration(deviceLibraryIdentifier: "DEV1", passTypeIdentifier: "pass.test", serialNumber: "S1")
            context.expectEqual(fetched?.pushToken, Data([0xCC, 0xDD]))

            try await db.deleteRegistration(deviceLibraryIdentifier: "DEV1", passTypeIdentifier: "pass.test", serialNumber: "S1")
            context.expectEqual(try await db.registrationCount(), 0)
        },
        TestCase("db.staleGenerationCannotDeleteNewerToken") { context in
            let db = try makeDatabase()
            try await db.migrate()
            _ = try await db.upsertRegistration(deviceLibraryIdentifier: "D", passTypeIdentifier: "P", serialNumber: "S", pushToken: Data([1]))
            _ = try await db.upsertRegistration(deviceLibraryIdentifier: "D", passTypeIdentifier: "P", serialNumber: "S", pushToken: Data([2]))
            context.expect(!(try await db.deleteRegistrationIfGenerationMatches(deviceLibraryIdentifier: "D", passTypeIdentifier: "P", serialNumber: "S", tokenGeneration: 1)))
            context.expectEqual(try await db.registrationCount(), 1)
            context.expect(try await db.deleteRegistrationIfGenerationMatches(deviceLibraryIdentifier: "D", passTypeIdentifier: "P", serialNumber: "S", tokenGeneration: 2))
        },
        TestCase("db.publicationIsAtomicAndRevisionsAdvance") { context in
            let db = try makeDatabase()
            try await db.migrate()
            let now = Date()
            let first = PassState(serialNumber: "S1", passTypeIdentifier: "P", revision: 1, contentHash: "h1", archiveBlob: Data("a".utf8), publishedAt: now, lastModifiedHTTP: HTTPDate.format(now), lastGeneratedAt: now, lastWalletChangeAt: nil)
            let outbox = [OutboxItem(serialNumber: "S1", passTypeIdentifier: "P", deviceLibraryIdentifier: "D", revision: 1, pushToken: Data([1]), tokenGeneration: 1)]
            try await db.publish(first, outbox: outbox)
            context.expectEqual(try await db.passState(serialNumber: "S1")?.revision, 1)
            context.expectEqual(try await db.pendingOutboxCount(), 1)
            let second = PassState(serialNumber: "S1", passTypeIdentifier: "P", revision: 2, contentHash: "h2", archiveBlob: Data("b".utf8), publishedAt: Date(), lastModifiedHTTP: HTTPDate.format(Date()), lastGeneratedAt: Date(), lastWalletChangeAt: nil)
            try await db.publish(second, outbox: [])
            context.expectEqual(try await db.passState(serialNumber: "S1")?.revision, 2)
        },
        TestCase("db.configRoundTrips") { context in
            let db = try makeDatabase()
            try await db.migrate()
            try await db.setConfigValue("serial-123", for: "wallet.serialNumber")
            context.expectEqual(try await db.configValue("wallet.serialNumber", as: String.self), "serial-123")
            try await db.setConfigValue(String?.none, for: "wallet.serialNumber")
            context.expectNil(try await db.configValue("wallet.serialNumber", as: String.self))
        },
        TestCase("db.activityIsBounded") { context in
            let db = try makeDatabase()
            try await db.migrate()
            for index in 0..<20 {
                try await db.insertActivity(ActivityRecord(occurredAt: Date(), kind: "qrRetrieved", title: "event \(index)", detail: nil, severity: "info", metadataJSON: nil))
            }
            try await db.pruneActivity(keep: 5, olderThan: 30)
            context.expectEqual(try await db.recentActivity(limit: 100).count, 5)
        },
        TestCase("install.linksExpireAndRevoke") { context in
            let store = InstallationLinkStore()
            let expired = await store.create(passTypeIdentifier: "P", serialNumber: "S", hostname: "wallet.example.com", ttl: -1)
            context.expectNil(await store.resolve(token: expired.token))
            let live = await store.create(passTypeIdentifier: "P", serialNumber: "S", hostname: "wallet.example.com", ttl: 600)
            context.expectNotNil(await store.resolve(token: live.token))
            context.expect(live.url.hasSuffix("/install/\(live.token)"), "install url should end with the token")
            await store.revokeAll()
            context.expectNil(await store.resolve(token: live.token))
        },
        TestCase("wallet.constantTimeEquals") { context in
            context.expect(WalletService.constantTimeEquals("abcdef", "abcdef"))
            context.expect(!WalletService.constantTimeEquals("abcdef", "abcde"))
            context.expect(!WalletService.constantTimeEquals("abcdef", "abcdeg"))
            context.expect(!WalletService.constantTimeEquals("", "x"))
        },
    ]
}
