import Foundation
import GymPassShared

/// Owns the Wallet protocol behaviour and the data the routes need. The HTTP
/// layer is intentionally thin and delegates here.
public actor WalletService {
    public struct PublishedPass: Sendable, Equatable {
        public var archive: Data
        public var revision: Int
        public var publishedAt: Date
    }

    public enum ConfigKey {
        public static let passTypeIdentifier = "wallet.passTypeIdentifier"
        public static let serialNumber = "wallet.serialNumber"
        public static let teamIdentifier = "wallet.teamIdentifier"
    }

    private let db: DatabaseManager
    private let secrets: any SecretStore
    private let crypto: CryptoBox
    public let installLinks: InstallationLinkStore

    public init(db: DatabaseManager, secrets: any SecretStore = KeychainStore(), crypto: CryptoBox) {
        self.db = db
        self.secrets = secrets
        self.crypto = crypto
        self.installLinks = InstallationLinkStore()
    }

    // MARK: - Identity

    public func setPassIdentity(passTypeIdentifier: String, serialNumber: String, teamIdentifier: String?) async throws {
        try await db.setConfigValue(passTypeIdentifier, for: ConfigKey.passTypeIdentifier)
        try await db.setConfigValue(serialNumber, for: ConfigKey.serialNumber)
        if let teamIdentifier {
            try await db.setConfigValue(teamIdentifier, for: ConfigKey.teamIdentifier)
        }
        _ = try await ensurePassToken(serialNumber: serialNumber)
    }

    public func passIdentity() async throws -> (passTypeIdentifier: String, serialNumber: String)? {
        let passType: String? = try await db.configValue(ConfigKey.passTypeIdentifier, as: String.self)
        let serial: String? = try await db.configValue(ConfigKey.serialNumber, as: String.self)
        guard let passType, let serial else { return nil }
        return (passType, serial)
    }

    /// Returns the stable per-pass authentication token, creating it if needed.
    public func ensurePassToken(serialNumber: String) async throws -> String {
        let key = KeychainStore.DynamicKey.passToken(serial: serialNumber)
        if let existing = try await secrets.getString(key) {
            return existing
        }
        let token = SecureRandom.token(byteCount: 32)
        try await secrets.set(token, for: key)
        return token
    }

    public func passToken(serialNumber: String) async throws -> String? {
        try await secrets.getString(KeychainStore.DynamicKey.passToken(serial: serialNumber))
    }

    // MARK: - Publication access

    public func publishedPass(serialNumber: String) async throws -> PublishedPass? {
        guard let state = try await db.passState(serialNumber: serialNumber) else { return nil }
        let archive = try crypto.open(state.archiveBlob)
        return PublishedPass(archive: archive, revision: state.revision, publishedAt: state.publishedAt)
    }

    public func registrationCount() async throws -> Int {
        try await db.registrationCount()
    }

    public func validatePassToken(passTypeIdentifier: String, serialNumber: String, token: String) async -> Bool {
        guard let expected = try? await passToken(serialNumber: serialNumber) else { return false }
        return Self.constantTimeEquals(expected, token)
    }

    // MARK: - Registration

    @discardableResult
    public func register(deviceLibraryIdentifier: String, passTypeIdentifier: String, serialNumber: String, pushToken: Data) async throws -> Bool {
        let outcome = try await db.upsertRegistration(
            deviceLibraryIdentifier: deviceLibraryIdentifier,
            passTypeIdentifier: passTypeIdentifier,
            serialNumber: serialNumber,
            pushToken: pushToken
        )
        return outcome.created
    }

    public func unregister(deviceLibraryIdentifier: String, passTypeIdentifier: String, serialNumber: String) async throws {
        try await db.deleteRegistration(
            deviceLibraryIdentifier: deviceLibraryIdentifier,
            passTypeIdentifier: passTypeIdentifier,
            serialNumber: serialNumber
        )
    }

    /// Serial numbers for this device and pass type with a revision newer than
    /// the supplied cursor, plus the newest revision across those passes.
    public func updatedSerialNumbers(deviceLibraryIdentifier: String, passTypeIdentifier: String, since cursor: Int?) async throws -> (serialNumbers: [String], lastUpdated: Int?) {
        let registrations = try await db.registrationsForDevice(
            deviceLibraryIdentifier: deviceLibraryIdentifier,
            passTypeIdentifier: passTypeIdentifier
        )
        var serials: [String] = []
        var maxRevision: Int?
        for registration in registrations {
            guard let state = try await db.passState(serialNumber: registration.serialNumber) else { continue }
            if let cursor, state.revision <= cursor { continue }
            serials.append(registration.serialNumber)
            maxRevision = max(maxRevision ?? 0, state.revision)
        }
        return (serials.sorted(), maxRevision)
    }

    // MARK: - Installation

    public func createInstallLink(hostname: String, ttl: TimeInterval = 900) async throws -> InstallLink {
        guard let identity = try await passIdentity() else {
            throw GymPassError.notConfigured("Wallet pass")
        }
        return await installLinks.create(
            passTypeIdentifier: identity.passTypeIdentifier,
            serialNumber: identity.serialNumber,
            hostname: hostname,
            ttl: ttl
        )
    }

    public func archiveForInstallToken(_ token: String) async -> (archive: Data, fileName: String)? {
        guard let link = await installLinks.resolve(token: token),
              let published = try? await publishedPass(serialNumber: link.serialNumber) else {
            return nil
        }
        return (published.archive, "\(link.serialNumber).pkpass")
    }

    // MARK: - Helpers

    public static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8)
        let y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<x.count {
            difference |= x[index] ^ y[index]
        }
        return difference == 0
    }
}
