import Foundation
import GymPassShared

public struct PassIdentity: Sendable, Equatable {
    public var passTypeIdentifier: String
    public var serialNumber: String
    public var teamIdentifier: String
    public init(passTypeIdentifier: String, serialNumber: String, teamIdentifier: String) {
        self.passTypeIdentifier = passTypeIdentifier
        self.serialNumber = serialNumber
        self.teamIdentifier = teamIdentifier
    }
}

public struct RefreshContext: Sendable {
    public var passIdentity: @Sendable () async -> PassIdentity?
    public var appearance: @Sendable () async -> PassAppearance
    public var location: @Sendable () async -> PassLocation?
    public var webServiceURL: @Sendable () async -> String?
    public var passToken: @Sendable (String) async -> String?
    public var policy: @Sendable () async -> RefreshPolicy
    public var expirationDate: @Sendable () async -> Date?

    public init(
        passIdentity: @escaping @Sendable () async -> PassIdentity?,
        appearance: @escaping @Sendable () async -> PassAppearance,
        location: @escaping @Sendable () async -> PassLocation?,
        webServiceURL: @escaping @Sendable () async -> String?,
        passToken: @escaping @Sendable (String) async -> String?,
        policy: @escaping @Sendable () async -> RefreshPolicy,
        expirationDate: @escaping @Sendable () async -> Date?
    ) {
        self.passIdentity = passIdentity
        self.appearance = appearance
        self.location = location
        self.webServiceURL = webServiceURL
        self.passToken = passToken
        self.policy = policy
        self.expirationDate = expirationDate
    }
}

/// Runs the QR retrieval and pass publication pipeline. Concurrency is
/// coalesced: overlapping manual/scheduled/recovery refreshes share one run.
public actor RefreshEngine {
    public enum Outcome: Sendable, Equatable {
        case changed(revision: Int)
        case unchanged
        case skipped
        case failed(String)

        public var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    private let puregym: PureGymAPI
    private let db: DatabaseManager
    private let crypto: CryptoBox
    private let passService: WalletPassService
    private let walletService: WalletService
    private let dispatcher: NotificationDispatcher
    private let activity: ActivityRecorder
    private let context: RefreshContext

    private var inFlight = false
    private var consecutiveFailures = 0
    private var lastOutcome: Outcome = .skipped

    public init(
        puregym: PureGymAPI,
        db: DatabaseManager,
        crypto: CryptoBox,
        passService: WalletPassService,
        walletService: WalletService,
        dispatcher: NotificationDispatcher,
        activity: ActivityRecorder,
        context: RefreshContext
    ) {
        self.puregym = puregym
        self.db = db
        self.crypto = crypto
        self.passService = passService
        self.walletService = walletService
        self.dispatcher = dispatcher
        self.activity = activity
        self.context = context
    }

    public var failures: Int { consecutiveFailures }

    public func nextDelay() async -> TimeInterval {
        let policy = await context.policy()
        let qrState = try? await db.qrState()
        let existingPass = try? await currentPassState()
        let qrStatus = QRStatus(
            present: qrState?.qrHash != nil,
            retrievedAt: qrState?.retrievedAt,
            expiresAt: qrState?.expiresAt,
            refreshAfter: qrState?.refreshAfter,
            changedAt: nil,
            reportedExpiryPassed: (qrState?.expiresAt ?? .distantFuture) < Date()
        )
        return RefreshScheduler.nextDelay(
            policy: policy,
            qr: qrStatus,
            failures: consecutiveFailures,
            hasPublishedPass: existingPass != nil
        )
    }

    public func refresh(trigger: RefreshTrigger) async -> Outcome {
        if inFlight {
            Log.puregym.debug("Refresh coalesced (another refresh is running)")
            return lastOutcome
        }
        inFlight = true
        defer { inFlight = false }

        do {
            let outcome = try await performRefresh(trigger: trigger)
            lastOutcome = outcome
            if case .failed = outcome {
                consecutiveFailures += 1
            } else {
                consecutiveFailures = 0
            }
            return outcome
        } catch let error as GymPassError {
            consecutiveFailures += 1
            await recordFailure(error)
            lastOutcome = .failed(error.code)
            return lastOutcome
        } catch {
            consecutiveFailures += 1
            let message = Redactor.redact(String(describing: error))
            await recordFailure(.internalError(message))
            lastOutcome = .failed("internal_error")
            return lastOutcome
        }
    }

    private func performRefresh(trigger: RefreshTrigger) async throws -> Outcome {
        let qr = try await puregym.fetchQRCode()
        let qrHash = ArchiveContentHash.sha256(qr.code)
        let previousQR = try await db.qrState()
        let previousPass = try await currentPassState()
        let qrChanged = previousQR?.qrHash != qrHash

        // A saved pass can be republished when non-QR content changes, so the
        // decision is always based on the full content identity.
        guard let identity = await context.passIdentity() else {
            if previousPass != nil {
                try await db.saveQRState(
                    QRState(
                        qrCiphertext: try crypto.seal(qr.code),
                        qrHash: qrHash,
                        retrievedAt: Date(),
                        expiresAt: qr.expiresAt,
                        refreshAfter: qr.refreshAt,
                        lastError: previousQR?.lastError
                    )
                )
                await activity.record(kind: .qrUnchanged, title: "PureGym checked", detail: "The existing access code is still current.")
                return .unchanged
            }
            // Keep the retrieved code for later, but do not publish.
            try await db.saveQRState(
                QRState(
                    qrCiphertext: try crypto.seal(qr.code),
                    qrHash: qrHash,
                    retrievedAt: Date(),
                    expiresAt: qr.expiresAt,
                    refreshAfter: qr.refreshAt,
                    lastError: "signing_unavailable"
                )
            )
            await activity.record(
                kind: .certificateWarning,
                title: "A signing certificate is required",
                detail: "GymPass retrieved a new access code but cannot create a Wallet pass yet."
            )
            return .failed("signing_unavailable")
        }

        let appearance = await context.appearance()
        let location = await context.location()
        let webServiceURL = await context.webServiceURL()
        let token: String?
        if webServiceURL != nil {
            token = try await walletService.ensurePassToken(serialNumber: identity.serialNumber)
        } else {
            token = nil
        }

        let inputs = PassBuildInputs(
            passTypeIdentifier: identity.passTypeIdentifier,
            teamIdentifier: identity.teamIdentifier,
            serialNumber: identity.serialNumber,
            authenticationToken: token ?? "",
            webServiceURL: webServiceURL,
            qrPayload: qr.code,
            appearance: appearance,
            location: location,
            expirationDate: await context.expirationDate(),
            relevantDate: nil,
            organizationName: "GymPass",
            description: "PureGym access code"
        )

        let contentIdentity = WalletPassService.contentIdentity(for: inputs)
        if contentIdentity == previousPass?.contentHash {
            try await db.saveQRState(
                QRState(
                    qrCiphertext: try crypto.seal(qr.code),
                    qrHash: qrHash,
                    retrievedAt: Date(),
                    expiresAt: qr.expiresAt,
                    refreshAfter: qr.refreshAt,
                    lastError: nil
                )
            )
            await activity.record(kind: .qrUnchanged, title: "PureGym checked", detail: "The existing access code is still current.")
            return .unchanged
        }

        let generated = try await passService.generate(inputs: inputs)
        let encryptedArchive = try crypto.seal(generated.archive)
        let revision = (previousPass?.revision ?? 0) + 1

        let registrations = try await db.registrations(forSerial: identity.serialNumber, passTypeIdentifier: identity.passTypeIdentifier)
        let outbox = registrations.map { registration in
            OutboxItem(
                serialNumber: identity.serialNumber,
                passTypeIdentifier: identity.passTypeIdentifier,
                deviceLibraryIdentifier: registration.deviceLibraryIdentifier,
                revision: revision,
                pushToken: registration.pushToken,
                tokenGeneration: registration.tokenGeneration
            )
        }

        let state = PassState(
            serialNumber: identity.serialNumber,
            passTypeIdentifier: identity.passTypeIdentifier,
            revision: revision,
            contentHash: contentIdentity,
            archiveBlob: encryptedArchive,
            publishedAt: Date(),
            lastModifiedHTTP: HTTPDate.format(Date()),
            lastGeneratedAt: Date(),
            lastWalletChangeAt: registrations.isEmpty ? nil : Date()
        )

        try await db.publish(state, outbox: outbox)
        try await db.saveQRState(
            QRState(
                qrCiphertext: try crypto.seal(qr.code),
                qrHash: qrHash,
                retrievedAt: Date(),
                expiresAt: qr.expiresAt,
                refreshAfter: qr.refreshAt,
                lastError: nil
            )
        )

        await activity.record(
            kind: .passPublished,
            title: "New pass ready",
            detail: qrChanged
                ? "A new PureGym access code was retrieved and a fresh Wallet pass was generated."
                : "The pass settings changed and a fresh Wallet pass was generated.",
            metadata: ["revision": String(revision), "trigger": trigger.rawValue, "qrChanged": qrChanged ? "true" : "false"]
        )

        if !registrations.isEmpty {
            await activity.record(
                kind: .devicesNotified,
                title: "Notifying Wallet devices",
                detail: "\(registrations.count) Wallet registration\(registrations.count == 1 ? "" : "s") will be told an update is available."
            )
            await dispatcher.processDue()
        }

        return .changed(revision: revision)
    }

    private func currentPassState() async throws -> PassState? {
        guard let identity = try await db.configValue(WalletService.ConfigKey.serialNumber, as: String.self) else {
            return nil
        }
        return try await db.passState(serialNumber: identity)
    }

    private func recordFailure(_ error: GymPassError) async {
        await activity.record(
            kind: error == .authenticationRequired ? .authRequiresAttention : .error,
            title: error == .authenticationRequired ? "PureGym needs you to sign in again" : "Could not refresh the access code",
            detail: error.userMessage
        )
    }
}
