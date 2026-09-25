import Foundation
import GymPassShared
import GRDB

public struct Registration: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "wallet_registration"
    public var deviceLibraryIdentifier: String
    public var passTypeIdentifier: String
    public var serialNumber: String
    public var pushToken: Data
    public var tokenGeneration: Int
    public var createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case deviceLibraryIdentifier = "device_library_identifier"
        case passTypeIdentifier = "pass_type_identifier"
        case serialNumber = "serial_number"
        case pushToken = "push_token"
        case tokenGeneration = "token_generation"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(deviceLibraryIdentifier: String, passTypeIdentifier: String, serialNumber: String, pushToken: Data, tokenGeneration: Int = 1, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.deviceLibraryIdentifier = deviceLibraryIdentifier
        self.passTypeIdentifier = passTypeIdentifier
        self.serialNumber = serialNumber
        self.pushToken = pushToken
        self.tokenGeneration = tokenGeneration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PassState: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "wallet_pass_state"
    public var serialNumber: String
    public var passTypeIdentifier: String
    public var revision: Int
    public var contentHash: String
    public var archiveBlob: Data
    public var publishedAt: Date
    public var lastModifiedHTTP: String
    public var lastGeneratedAt: Date
    public var lastWalletChangeAt: Date?

    enum CodingKeys: String, CodingKey {
        case serialNumber = "serial_number"
        case passTypeIdentifier = "pass_type_identifier"
        case revision
        case contentHash = "content_hash"
        case archiveBlob = "archive_blob"
        case publishedAt = "published_at"
        case lastModifiedHTTP = "last_modified_http"
        case lastGeneratedAt = "last_generated_at"
        case lastWalletChangeAt = "last_wallet_change_at"
    }

    public init(serialNumber: String, passTypeIdentifier: String, revision: Int, contentHash: String, archiveBlob: Data, publishedAt: Date, lastModifiedHTTP: String, lastGeneratedAt: Date, lastWalletChangeAt: Date?) {
        self.serialNumber = serialNumber
        self.passTypeIdentifier = passTypeIdentifier
        self.revision = revision
        self.contentHash = contentHash
        self.archiveBlob = archiveBlob
        self.publishedAt = publishedAt
        self.lastModifiedHTTP = lastModifiedHTTP
        self.lastGeneratedAt = lastGeneratedAt
        self.lastWalletChangeAt = lastWalletChangeAt
    }
}

public struct QRState: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "qr_state"
    public static let singletonID = 1
    public var id: Int
    public var qrCiphertext: Data?
    public var qrHash: String?
    public var retrievedAt: Date?
    public var expiresAt: Date?
    public var refreshAfter: Date?
    public var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case qrCiphertext = "qr_ciphertext"
        case qrHash = "qr_hash"
        case retrievedAt = "retrieved_at"
        case expiresAt = "expires_at"
        case refreshAfter = "refresh_after"
        case lastError = "last_error"
    }

    public init(id: Int = QRState.singletonID, qrCiphertext: Data? = nil, qrHash: String? = nil, retrievedAt: Date? = nil, expiresAt: Date? = nil, refreshAfter: Date? = nil, lastError: String? = nil) {
        self.id = id
        self.qrCiphertext = qrCiphertext
        self.qrHash = qrHash
        self.retrievedAt = retrievedAt
        self.expiresAt = expiresAt
        self.refreshAfter = refreshAfter
        self.lastError = lastError
    }
}

public struct OutboxItem: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "notification_outbox"
    public var id: Int64?
    public var serialNumber: String
    public var passTypeIdentifier: String
    public var deviceLibraryIdentifier: String
    public var revision: Int
    public var pushToken: Data
    public var tokenGeneration: Int
    public var attempts: Int
    public var nextAttemptAt: Date
    public var state: String
    public var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case serialNumber = "serial_number"
        case passTypeIdentifier = "pass_type_identifier"
        case deviceLibraryIdentifier = "device_library_identifier"
        case revision
        case pushToken = "push_token"
        case tokenGeneration = "token_generation"
        case attempts
        case nextAttemptAt = "next_attempt_at"
        case state
        case lastError = "last_error"
    }

    public init(id: Int64? = nil, serialNumber: String, passTypeIdentifier: String, deviceLibraryIdentifier: String, revision: Int, pushToken: Data, tokenGeneration: Int, attempts: Int = 0, nextAttemptAt: Date = Date(), state: String = "pending", lastError: String? = nil) {
        self.id = id
        self.serialNumber = serialNumber
        self.passTypeIdentifier = passTypeIdentifier
        self.deviceLibraryIdentifier = deviceLibraryIdentifier
        self.revision = revision
        self.pushToken = pushToken
        self.tokenGeneration = tokenGeneration
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
        self.state = state
        self.lastError = lastError
    }
}

public struct ActivityRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "activity_event"
    public var id: Int64?
    public var occurredAt: Date
    public var kind: String
    public var title: String
    public var detail: String?
    public var severity: String
    public var metadataJSON: String?

    enum CodingKeys: String, CodingKey {
        case id
        case occurredAt = "occurred_at"
        case kind, title, detail, severity
        case metadataJSON = "metadata_json"
    }

    public init(id: Int64? = nil, occurredAt: Date, kind: String, title: String, detail: String?, severity: String, metadataJSON: String?) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.title = title
        self.detail = detail
        self.severity = severity
        self.metadataJSON = metadataJSON
    }

    public func toEvent() -> ActivityEvent {
        let metadata: [String: String]
        if let json = metadataJSON, let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            metadata = decoded
        } else {
            metadata = [:]
        }
        return ActivityEvent(
            id: id,
            occurredAt: occurredAt,
            kind: ActivityKind(rawValue: kind) ?? .error,
            title: title,
            detail: detail,
            metadata: metadata
        )
    }
}

public struct ConfigRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "app_config"
    public var key: String
    public var value: Data

    public init(key: String, value: Data) {
        self.key = key
        self.value = value
    }
}
