import Foundation
import GymPassShared
import GRDB

public actor DatabaseManager {
    private let pool: DatabasePool
    public let path: String
    private(set) public var migrationVersion: String = "unknown"

    public init(path: String? = nil) throws {
        let resolved = path ?? AppPaths.databaseURL().path
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5)
        configuration.maximumReaderCount = 4
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        self.path = resolved
        self.pool = try DatabasePool(path: resolved, configuration: configuration)
    }

    public func migrate() async throws {
        let migrator = Self.makeMigrator()
        try migrator.migrate(pool)
        migrationVersion = "v1"
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS wallet_registration (
                    device_library_identifier TEXT NOT NULL,
                    pass_type_identifier       TEXT NOT NULL,
                    serial_number              TEXT NOT NULL,
                    push_token                 BLOB NOT NULL,
                    token_generation           INTEGER NOT NULL DEFAULT 1,
                    created_at                 TEXT NOT NULL,
                    updated_at                 TEXT NOT NULL,
                    PRIMARY KEY (device_library_identifier, pass_type_identifier, serial_number)
                );
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_registration_serial
                    ON wallet_registration(serial_number, pass_type_identifier);
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS wallet_pass_state (
                    serial_number         TEXT PRIMARY KEY,
                    pass_type_identifier  TEXT NOT NULL,
                    revision              INTEGER NOT NULL,
                    content_hash          TEXT NOT NULL,
                    archive_blob          BLOB NOT NULL,
                    published_at          TEXT NOT NULL,
                    last_modified_http    TEXT NOT NULL,
                    last_generated_at     TEXT NOT NULL,
                    last_wallet_change_at TEXT
                );
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS qr_state (
                    id               INTEGER PRIMARY KEY CHECK (id = 1),
                    qr_ciphertext    BLOB,
                    qr_hash          TEXT,
                    retrieved_at     TEXT,
                    expires_at       TEXT,
                    refresh_after    TEXT,
                    last_error       TEXT
                );
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS notification_outbox (
                    id               INTEGER PRIMARY KEY AUTOINCREMENT,
                    serial_number    TEXT NOT NULL,
                    revision         INTEGER NOT NULL,
                    push_token       BLOB NOT NULL,
                    token_generation INTEGER NOT NULL,
                    attempts         INTEGER NOT NULL DEFAULT 0,
                    next_attempt_at  TEXT NOT NULL,
                    state            TEXT NOT NULL,
                    last_error       TEXT
                );
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_outbox_state
                    ON notification_outbox(state, next_attempt_at);
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS activity_event (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    occurred_at   TEXT NOT NULL,
                    kind          TEXT NOT NULL,
                    title         TEXT NOT NULL,
                    detail        TEXT,
                    severity      TEXT NOT NULL,
                    metadata_json TEXT
                );
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_activity_time
                    ON activity_event(occurred_at DESC);
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS app_config (
                    key   TEXT PRIMARY KEY,
                    value BLOB NOT NULL
                );
                """)
        }
        return migrator
    }

    public func close() {
        try? pool.close()
    }

    public func fileSize() -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }

    // MARK: - Registrations

    public func registrationCount() async throws -> Int {
        try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wallet_registration") ?? 0
        }
    }

    public func registrationsForDevice(deviceLibraryIdentifier: String, passTypeIdentifier: String) async throws -> [Registration] {
        try await pool.read { db in
            try Registration.fetchAll(
                db,
                sql: """
                    SELECT * FROM wallet_registration
                    WHERE device_library_identifier = ? AND pass_type_identifier = ?
                    """,
                arguments: [deviceLibraryIdentifier, passTypeIdentifier]
            )
        }
    }

    public func registrations(forSerial serial: String, passTypeIdentifier: String) async throws -> [Registration] {
        try await pool.read { db in
            try Registration.fetchAll(
                db,
                sql: "SELECT * FROM wallet_registration WHERE serial_number = ? AND pass_type_identifier = ?",
                arguments: [serial, passTypeIdentifier]
            )
        }
    }

    public func registration(deviceLibraryIdentifier: String, passTypeIdentifier: String, serialNumber: String) async throws -> Registration? {
        try await pool.read { db in
            try Registration.fetchOne(
                db,
                sql: """
                    SELECT * FROM wallet_registration
                    WHERE device_library_identifier = ? AND pass_type_identifier = ? AND serial_number = ?
                    """,
                arguments: [deviceLibraryIdentifier, passTypeIdentifier, serialNumber]
            )
        }
    }

    /// Upserts a registration. Returns `true` when the row was newly created.
    @discardableResult
    public func upsertRegistration(
        deviceLibraryIdentifier: String,
        passTypeIdentifier: String,
        serialNumber: String,
        pushToken: Data
    ) async throws -> (created: Bool, tokenGeneration: Int) {
        try await pool.write { db in
            let existing = try Registration.fetchOne(
                db,
                sql: """
                    SELECT * FROM wallet_registration
                    WHERE device_library_identifier = ? AND pass_type_identifier = ? AND serial_number = ?
                    """,
                arguments: [deviceLibraryIdentifier, passTypeIdentifier, serialNumber]
            )
            let now = Date()
            if let existing {
                let tokenChanged = existing.pushToken != pushToken
                let generation = tokenChanged ? existing.tokenGeneration + 1 : existing.tokenGeneration
                try db.execute(
                    sql: """
                        UPDATE wallet_registration
                        SET push_token = ?, token_generation = ?, updated_at = ?
                        WHERE device_library_identifier = ? AND pass_type_identifier = ? AND serial_number = ?
                        """,
                    arguments: [pushToken, generation, now, deviceLibraryIdentifier, passTypeIdentifier, serialNumber]
                )
                return (false, generation)
            } else {
                try db.execute(
                    sql: """
                        INSERT INTO wallet_registration
                        (device_library_identifier, pass_type_identifier, serial_number, push_token, token_generation, created_at, updated_at)
                        VALUES (?, ?, ?, ?, 1, ?, ?)
                        """,
                    arguments: [deviceLibraryIdentifier, passTypeIdentifier, serialNumber, pushToken, now, now]
                )
                return (true, 1)
            }
        }
    }

    public func deleteRegistration(deviceLibraryIdentifier: String, passTypeIdentifier: String, serialNumber: String) async throws {
        try await pool.write { db in
            try db.execute(
                sql: """
                    DELETE FROM wallet_registration
                    WHERE device_library_identifier = ? AND pass_type_identifier = ? AND serial_number = ?
                    """,
                arguments: [deviceLibraryIdentifier, passTypeIdentifier, serialNumber]
            )
        }
    }

    /// Deletes a registration only if the token generation still matches.
    public func deleteRegistrationIfGenerationMatches(deviceLibraryIdentifier: String, passTypeIdentifier: String, serialNumber: String, tokenGeneration: Int) async throws -> Bool {
        try await pool.write { db in
            let existing = try Registration.fetchOne(
                db,
                sql: """
                    SELECT * FROM wallet_registration
                    WHERE device_library_identifier = ? AND pass_type_identifier = ? AND serial_number = ?
                    """,
                arguments: [deviceLibraryIdentifier, passTypeIdentifier, serialNumber]
            )
            guard let existing, existing.tokenGeneration == tokenGeneration else { return false }
            try db.execute(
                sql: """
                    DELETE FROM wallet_registration
                    WHERE device_library_identifier = ? AND pass_type_identifier = ? AND serial_number = ?
                    """,
                arguments: [deviceLibraryIdentifier, passTypeIdentifier, serialNumber]
            )
            return true
        }
    }

    public func deleteAllRegistrations() async throws {
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM wallet_registration")
        }
    }

    // MARK: - Pass state

    public func passState(serialNumber: String) async throws -> PassState? {
        try await pool.read { db in
            try PassState.fetchOne(db, sql: "SELECT * FROM wallet_pass_state WHERE serial_number = ?", arguments: [serialNumber])
        }
    }

    public func allPassStates() async throws -> [PassState] {
        try await pool.read { db in
            try PassState.fetchAll(db, sql: "SELECT * FROM wallet_pass_state")
        }
    }

    public func deletePassState() async throws {
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM wallet_pass_state")
        }
    }

    /// Atomically commits a new published revision together with its outbox rows.
    public func publish(_ state: PassState, outbox: [OutboxItem]) async throws {
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO wallet_pass_state
                    (serial_number, pass_type_identifier, revision, content_hash, archive_blob, published_at, last_modified_http, last_generated_at, last_wallet_change_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(serial_number) DO UPDATE SET
                        pass_type_identifier = excluded.pass_type_identifier,
                        revision = excluded.revision,
                        content_hash = excluded.content_hash,
                        archive_blob = excluded.archive_blob,
                        published_at = excluded.published_at,
                        last_modified_http = excluded.last_modified_http,
                        last_generated_at = excluded.last_generated_at,
                        last_wallet_change_at = excluded.last_wallet_change_at
                    """,
                arguments: [
                    state.serialNumber, state.passTypeIdentifier, state.revision,
                    state.contentHash, state.archiveBlob, state.publishedAt,
                    state.lastModifiedHTTP, state.lastGeneratedAt, state.lastWalletChangeAt,
                ]
            )
            for item in outbox {
                try item.insert(db)
            }
        }
    }

    // MARK: - QR state

    public func qrState() async throws -> QRState? {
        try await pool.read { db in
            try QRState.fetchOne(db, sql: "SELECT * FROM qr_state WHERE id = 1")
        }
    }

    public func saveQRState(_ state: QRState) async throws {
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO qr_state (id, qr_ciphertext, qr_hash, retrieved_at, expires_at, refresh_after, last_error)
                    VALUES (1, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        qr_ciphertext = excluded.qr_ciphertext,
                        qr_hash = excluded.qr_hash,
                        retrieved_at = excluded.retrieved_at,
                        expires_at = excluded.expires_at,
                        refresh_after = excluded.refresh_after,
                        last_error = excluded.last_error
                    """,
                arguments: [state.qrCiphertext, state.qrHash, state.retrievedAt, state.expiresAt, state.refreshAfter, state.lastError]
            )
        }
    }

    // MARK: - Outbox

    public func dueOutbox(now: Date, limit: Int = 50) async throws -> [OutboxItem] {
        try await pool.read { db in
            try OutboxItem.fetchAll(
                db,
                sql: "SELECT * FROM notification_outbox WHERE state = 'pending' AND next_attempt_at <= ? ORDER BY id ASC LIMIT ?",
                arguments: [now, limit]
            )
        }
    }

    public func pendingOutboxCount() async throws -> Int {
        try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notification_outbox WHERE state = 'pending'") ?? 0
        }
    }

    public func markOutboxDone(id: Int64) async throws {
        try await pool.write { db in
            try db.execute(sql: "UPDATE notification_outbox SET state = 'done' WHERE id = ?", arguments: [id])
        }
    }

    public func markOutboxFailed(id: Int64, nextAttemptAt: Date, error: String) async throws {
        try await pool.write { db in
            try db.execute(
                sql: "UPDATE notification_outbox SET attempts = attempts + 1, next_attempt_at = ?, last_error = ? WHERE id = ?",
                arguments: [nextAttemptAt, error, id]
            )
        }
    }

    public func pruneOutbox() async throws {
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM notification_outbox WHERE state = 'done' AND id NOT IN (SELECT id FROM notification_outbox WHERE state = 'done' ORDER BY id DESC LIMIT 200)")
        }
    }

    // MARK: - Activity

    public func insertActivity(_ record: ActivityRecord) async throws {
        try await pool.write { db in
            var copy = record
            try copy.insert(db)
        }
    }

    public func recentActivity(limit: Int = 200) async throws -> [ActivityEvent] {
        try await pool.read { db in
            let records = try ActivityRecord.fetchAll(
                db,
                sql: "SELECT * FROM activity_event ORDER BY occurred_at DESC, id DESC LIMIT ?",
                arguments: [limit]
            )
            return records.map { $0.toEvent() }
        }
    }

    public func pruneActivity(keep: Int = 500, olderThan days: Int = 30) async throws {
        try await pool.write { db in
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            try db.execute(sql: "DELETE FROM activity_event WHERE occurred_at < ?", arguments: [cutoff])
            try db.execute(
                sql: "DELETE FROM activity_event WHERE id NOT IN (SELECT id FROM activity_event ORDER BY id DESC LIMIT ?)",
                arguments: [keep]
            )
        }
    }

    // MARK: - Config

    public func configValue<T: Codable & Sendable>(_ key: String, as type: T.Type) async throws -> T? {
        try await pool.read { db in
            guard let record = try ConfigRecord.fetchOne(db, sql: "SELECT * FROM app_config WHERE key = ?", arguments: [key]) else {
                return nil
            }
            return try JSONDecoder().decode(T.self, from: record.value)
        }
    }

    public func setConfigValue<T: Codable & Sendable>(_ value: T?, for key: String) async throws {
        try await pool.write { db in
            guard let value else {
                try db.execute(sql: "DELETE FROM app_config WHERE key = ?", arguments: [key])
                return
            }
            let data = try JSONEncoder().encode(value)
            try db.execute(
                sql: """
                    INSERT INTO app_config (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [key, data]
            )
        }
    }
}
