import Foundation
import GymPassShared

/// Writes human-readable activity events and keeps the table bounded.
public actor ActivityRecorder {
    private let db: DatabaseManager

    public init(db: DatabaseManager) {
        self.db = db
    }

    public func record(kind: ActivityKind, title: String, detail: String? = nil, metadata: [String: String] = [:]) async {
        let metadataJSON: String? = {
            guard !metadata.isEmpty, let data = try? JSONEncoder().encode(metadata) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        let record = ActivityRecord(
            occurredAt: Date(),
            kind: kind.rawValue,
            title: title,
            detail: detail,
            severity: kind.isProblem ? "warning" : "info",
            metadataJSON: metadataJSON
        )
        do {
            try await db.insertActivity(record)
            try await db.pruneActivity()
        } catch {
            Log.database.error("Could not record activity: \(Redactor.redact(String(describing: error)), privacy: .public)")
        }
    }

    public func recent(limit: Int = 200) async -> [ActivityEvent] {
        (try? await db.recentActivity(limit: limit)) ?? []
    }
}

public actor NotificationDispatcher {
    private let db: DatabaseManager
    private let apns: APNsSending
    private let activity: ActivityRecorder
    private let policyProvider: @Sendable (String) async -> WalletAPNsPolicy?
    private let encoder = JSONEncoder()

    public init(
        db: DatabaseManager,
        apns: APNsSending,
        activity: ActivityRecorder,
        policyProvider: @escaping @Sendable (String) async -> WalletAPNsPolicy?
    ) {
        self.db = db
        self.apns = apns
        self.activity = activity
        self.policyProvider = policyProvider
    }

    public func pendingCount() async -> Int {
        (try? await db.pendingOutboxCount()) ?? 0
    }

    /// Processes due notifications. Safe to call frequently; does nothing when
    /// the outbox is empty.
    public func processDue(now: Date = Date()) async {
        guard let items = try? await db.dueOutbox(now: now) else { return }
        for item in items {
            guard let policy = await policyProvider(item.passTypeIdentifier) else {
                await scheduleRetry(item, error: "No signing identity for notifications")
                continue
            }
            let result = await apns.send(pushToken: item.pushToken, policy: policy)
            switch result {
            case .accepted:
                try? await db.markOutboxDone(id: item.id ?? 0)
                await activity.record(
                    kind: .notificationAccepted,
                    title: "Apple accepted the update notification",
                    detail: "Apple will ask registered Wallet devices to fetch the new pass."
                )
            case .invalidToken(let reason):
                await removeRegistrationIfCurrent(item)
                try? await db.markOutboxDone(id: item.id ?? 0)
                await activity.record(
                    kind: .notificationFailed,
                    title: "A Wallet registration is no longer valid",
                    detail: "The device will re-register automatically the next time Wallet checks."
                )
                _ = reason
            case .transient(let status, let reason):
                await scheduleRetry(item, error: "Transient APNs error \(status) \(reason ?? "")")
            case .topicMismatch(let reason):
                await scheduleRetry(item, error: "APNs topic mismatch: \(reason ?? "unknown")", longDelay: true)
            case .rejected(let status, let reason):
                await scheduleRetry(item, error: "APNs rejected \(status): \(reason ?? "unknown")")
            }
            try? await db.pruneOutbox()
        }
    }

    private func removeRegistrationIfCurrent(_ item: OutboxItem) async {
        _ = try? await db.deleteRegistrationIfGenerationMatches(
            deviceLibraryIdentifier: item.deviceLibraryIdentifier,
            passTypeIdentifier: item.passTypeIdentifier,
            serialNumber: item.serialNumber,
            tokenGeneration: item.tokenGeneration
        )
    }

    private func scheduleRetry(_ item: OutboxItem, error: String, longDelay: Bool = false) async {
        let attempt = item.attempts + 1
        let base = longDelay ? 900.0 : 60.0
        let delay = min(base * pow(2, Double(min(attempt, 6))), 3600)
        let jitter = Double(Int.random(in: 0...30))
        let next = Date().addingTimeInterval(delay + jitter)
        try? await db.markOutboxFailed(id: item.id ?? 0, nextAttemptAt: next, error: error)
    }
}
