import Foundation
import AppKit
import CryptoKit
import GymPassCore
import GymPassShared

/// Owns all agent state and orchestration. The GUI only ever talks to this
/// through the loopback control API.
public actor AgentRuntime {
    public let demoMode: Bool
    public let controlPort: Int
    public let walletPort: Int
    public let controlToken: String

    let database: DatabaseManager
    let secrets: any SecretStore
    let crypto: CryptoBox
    let activity: ActivityRecorder
    let walletService: WalletService
    let signingStore: SigningIdentityStore
    let passService: WalletPassService
    let puregym: any PureGymAPI
    let apns: any APNsSending
    let dispatcher: NotificationDispatcher
    let stats: ServerStats
    let installer: AgentInstaller

    var config: AgentConfiguration = .default
    private(set) var engine: RefreshEngine?
    private var walletServer: WalletHTTPServer?
    private var controlServer: ControlServer?
    var tunnel: CloudflareTunnelProvider?
    private let powerAssertion = PowerAssertion()

    let startedAt = Date()
    private var schedulerTask: Task<Void, Never>?
    private var outboxTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    var lastAPNsDescription: String?
    var lastPublicEndpoint: PublicEndpointStatus?
    var lastSigningSelfTest: (Date, Bool, String)?

    // MARK: - Construction

    public static func make(demoMode: Bool) async throws -> AgentRuntime {
        try AppPaths.ensureDirectories()

        let databasePath: String
        let secrets: any SecretStore
        let puregym: any PureGymAPI
        let dataKey: Data

        if demoMode {
            databasePath = AppPaths.applicationSupport().appendingPathComponent("demo.sqlite").path
            let memory = InMemorySecretStore()
            secrets = memory
            puregym = MockPureGymClient(changeEverySeconds: 120, validitySeconds: 7 * 24 * 3600)
            dataKey = Data(SHA256.hash(data: Data("gympass-demo-data-key".utf8)))
        } else {
            databasePath = AppPaths.databaseURL().path
            let keychain = KeychainStore()
            secrets = keychain
            puregym = PureGymClient()
            if let existing = try await keychain.get(KeychainStore.Key.dataKey.rawValue) {
                dataKey = existing
            } else {
                let generated = CryptoBox.randomKey()
                try await keychain.set(generated, for: KeychainStore.Key.dataKey.rawValue)
                dataKey = generated
            }
        }

        let database = try DatabaseManager(path: databasePath)
        try await database.migrate()
        let crypto = CryptoBox(key: dataKey)
        let activity = ActivityRecorder(db: database)
        let walletService = WalletService(db: database, secrets: secrets, crypto: crypto)
        let signingStore = SigningIdentityStore(secrets: secrets)
        let passService = WalletPassService(signer: PassSigner(signingStore: signingStore))

        let apns: any APNsSending
        if demoMode {
            apns = MockAPNsClient()
        } else {
            apns = APNsClient(environment: .production) { [weak signingStore] in
                guard let signingStore else { return nil }
                return try? await signingStore.loadIdentity()
            }
        }

        let dispatcher = NotificationDispatcher(db: database, apns: apns, activity: activity) { passType in
            WalletAPNsPolicy(topic: passType)
        }

        let controlToken = SecureRandom.token(byteCount: 32)
        return AgentRuntime(
            demoMode: demoMode,
            database: database,
            secrets: secrets,
            crypto: crypto,
            activity: activity,
            walletService: walletService,
            signingStore: signingStore,
            passService: passService,
            puregym: puregym,
            apns: apns,
            dispatcher: dispatcher,
            stats: ServerStats(),
            installer: AgentInstaller(executablePath: Bundle.main.executablePath ?? "", useSMAppService: false),
            controlToken: controlToken,
            controlPort: demoMode ? 18955 : 8755,
            walletPort: demoMode ? 18954 : 8754
        )
    }

    init(
        demoMode: Bool,
        database: DatabaseManager,
        secrets: any SecretStore,
        crypto: CryptoBox,
        activity: ActivityRecorder,
        walletService: WalletService,
        signingStore: SigningIdentityStore,
        passService: WalletPassService,
        puregym: any PureGymAPI,
        apns: any APNsSending,
        dispatcher: NotificationDispatcher,
        stats: ServerStats,
        installer: AgentInstaller,
        controlToken: String,
        controlPort: Int,
        walletPort: Int
    ) {
        self.demoMode = demoMode
        self.database = database
        self.secrets = secrets
        self.crypto = crypto
        self.activity = activity
        self.walletService = walletService
        self.signingStore = signingStore
        self.passService = passService
        self.puregym = puregym
        self.apns = apns
        self.dispatcher = dispatcher
        self.stats = stats
        self.installer = installer
        self.controlToken = controlToken
        self.controlPort = controlPort
        self.walletPort = walletPort
    }

    // MARK: - Lifecycle

    public func start() async throws {
        config = (try? await database.configValue(AgentConfiguration.configKey, as: AgentConfiguration.self)) ?? .default
        await restorePureGymTokens()

        let context = makeRefreshContext()
        let engine = RefreshEngine(
            puregym: puregym,
            db: database,
            crypto: crypto,
            passService: passService,
            walletService: walletService,
            dispatcher: dispatcher,
            activity: activity,
            context: context
        )
        self.engine = engine

        let walletServer = WalletHTTPServer(
            port: walletPort,
            service: walletService,
            stats: stats,
            publicHostnameProvider: { [weak self] in await self?.config.tunnel.publicHostname }
        )
        self.walletServer = walletServer
        try await walletServer.start()

        let controlServer = ControlServer(
            port: controlPort,
            token: controlToken,
            handler: { [weak self] request in
                guard let self else { return .failure(AgentErrorPayload(code: "agent_unavailable", message: "The agent is not available.")) }
                return await self.handle(request)
            },
            statusProvider: { [weak self] in
                guard let self else { return .unavailableSnapshot() }
                return await self.statusSnapshot()
            },
            activityProvider: { [weak self] limit in
                guard let self else { return [] }
                return await self.activity.recent(limit: limit)
            }
        )
        self.controlServer = controlServer
        try await controlServer.start()

        try writeControlEndpointFile()
        await activity.record(kind: .puregymChecked, title: "GymPass started", detail: demoMode ? "Running in demo mode." : "Background service is running.")
        await startTunnelIfConfigured()
        startSchedulerLoop()
        startOutboxLoop()
        installSystemObservers()
        await updatePowerAssertion()

        // Validate the code shortly after launch.
        Task { [weak self] in
            _ = await self?.engine?.refresh(trigger: .startup)
        }
    }

    public func stop() async {
        schedulerTask?.cancel()
        outboxTask?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        await tunnel?.stop()
        await walletServer?.stop()
        await controlServer?.stop()
        await powerAssertion.disable()
        try? FileManager.default.removeItem(at: AppPaths.controlEndpointURL())
        await database.close()
    }

    // MARK: - Loops

    private func startSchedulerLoop() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.engine?.nextDelay() ?? 3600
                try? await Task.sleep(nanoseconds: UInt64(max(30, delay) * 1_000_000_000))
                if Task.isCancelled { return }
                _ = await self.engine?.refresh(trigger: .scheduled)
            }
        }
    }

    private func startOutboxLoop() {
        outboxTask?.cancel()
        outboxTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.dispatcher.processDue()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    private func installSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { [weak self] in
                await self?.activity.record(kind: .puregymChecked, title: "Mac woke up", detail: "Validating the access code.")
                _ = await self?.engine?.refresh(trigger: .wake)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: nil) { [weak self] _ in
            Task { [weak self] in
                await self?.activity.record(kind: .puregymChecked, title: "System clock changed", detail: "Recomputing the refresh schedule.")
                await self?.startSchedulerLoopRestart()
            }
        })
    }

    func startSchedulerLoopRestart() {
        startSchedulerLoop()
    }

    // MARK: - Refresh context

    private func makeRefreshContext() -> RefreshContext {
        RefreshContext(
            passIdentity: { [weak self] in await self?.currentPassIdentity() },
            appearance: { [weak self] in await self?.config.appearance ?? .default },
            location: { [weak self] in await self?.config.location },
            webServiceURL: { [weak self] in
                guard let hostname = await self?.config.tunnel.publicHostname else { return nil }
                return "https://\(hostname)"
            },
            passToken: { [weak self] serial in try? await self?.walletService.ensurePassToken(serialNumber: serial) },
            policy: { [weak self] in await self?.config.policy ?? .default },
            expirationDate: { nil }
        )
    }

    func currentPassIdentity() async -> PassIdentity? {
        guard let info = try? await signingStore.info(),
              let passType = info.passTypeIdentifier,
              let team = info.teamIdentifier else { return nil }
        guard let serial = try? await walletService.passIdentity()?.serialNumber else { return nil }
        return PassIdentity(passTypeIdentifier: passType, serialNumber: serial, teamIdentifier: team)
    }

    // MARK: - Tunnel

    func restartTunnel() async {
        await tunnel?.stop()
        tunnel = nil
        await startTunnelIfConfigured()
    }

    private func startTunnelIfConfigured() async {
        guard config.tunnel.provider == .cloudflareQuick || config.tunnel.publicHostname != nil || config.tunnel.hasStoredCredentials else {
            return
        }
        let provider = CloudflareTunnelProvider(
            configuration: config.tunnel,
            walletPort: walletPort,
            tokenProvider: { [weak self] in
                guard let self else { return nil }
                return try? await self.secrets.getString(KeychainStore.Key.tunnelCredentials.rawValue)
            }
        )
        tunnel = provider
        do {
            try await provider.start()
            await activity.record(kind: .tunnelState, title: "Automatic updates started", detail: config.tunnel.publicHostname.map { "Reachable at \($0)." })
        } catch {
            await activity.record(kind: .tunnelState, title: "Automatic updates could not start", detail: (error as? GymPassError)?.userMessage)
        }
    }

    // MARK: - Config persistence

    func saveConfig() async {
        try? await database.setConfigValue(config, for: AgentConfiguration.configKey)
    }

    func writeControlEndpointFile() throws {
        let endpoint = ControlEndpointFile(
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            controlPort: controlPort,
            walletPort: walletPort,
            token: controlToken,
            protocolVersion: AgentProtocol.version,
            startedAt: startedAt
        )
        let data = try JSONEncoder().encode(endpoint)
        let url = AppPaths.controlEndpointURL()
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        AppPaths.restrictPermissions(url)
    }

    private func restorePureGymTokens() async {
        guard let data = try? await secrets.get(KeychainStore.Key.puregymTokens.rawValue),
              let tokens = try? JSONDecoder().decode(PureGymTokens.self, from: data) else { return }
        await puregym.setTokens(tokens)
    }

    func updatePowerAssertion() async {
        if config.preferences.keepMacAwake {
            powerAssertion.enable()
        } else {
            powerAssertion.disable()
        }
    }

    // MARK: - Status

    public func statusSnapshot() async -> StatusSnapshot {
        let info = try? await signingStore.info()
        let qrState = try? await database.qrState()
        let passState = try? await database.passState(serialNumber: (try? await walletService.passIdentity()?.serialNumber) ?? "")
        let registrationCount = (try? await walletService.registrationCount()) ?? 0
        let tokenData = try? await secrets.get(KeychainStore.Key.puregymTokens.rawValue)
        let tokens = tokenData.flatMap { try? JSONDecoder().decode(PureGymTokens.self, from: $0) }
        let failures = await engine?.failures ?? 0
        let tunnelStatus = await tunnel?.status() ?? TunnelStatus(state: config.tunnel.publicHostname == nil && !config.tunnel.hasStoredCredentials ? .notConfigured : .unavailable, provider: config.tunnel.provider, publicHostname: config.tunnel.publicHostname, binaryAvailable: TunnelBinaryLocator.locate() != nil)
        let pending = await dispatcher.pendingCount()
        let installation = await installer.status()

        let signingState: ServiceState = {
            guard let info else { return .notConfigured }
            switch info.kind {
            case .valid: return .healthy
            case .expiringSoon: return .warning
            case .expired, .missingPrivateKey, .wrongPassType, .signingFailed: return .unavailable
            case .notConfigured: return .notConfigured
            }
        }()

        let puregymState: ServiceState = {
            if tokens == nil { return .notConfigured }
            if failures > 0 { return .warning }
            if config.accountEmail != nil { return .healthy }
            return .waiting
        }()

        let walletState: ServiceState = {
            if passState == nil { return signingState == .healthy ? .waiting : .notConfigured }
            return .healthy
        }()

        let qrStatus = QRStatus(
            present: qrState?.qrHash != nil,
            retrievedAt: qrState?.retrievedAt,
            expiresAt: qrState?.expiresAt,
            refreshAfter: qrState?.refreshAfter,
            changedAt: nil,
            reportedExpiryPassed: (qrState?.expiresAt ?? .distantFuture) < Date()
        )

        let apnsState: ServiceState = {
            if demoMode { return .healthy }
            if registrationCount == 0 { return .waiting }
            return pending > 0 ? .working : .healthy
        }()

        let serverStatus = ServerStatus(
            state: .healthy,
            host: "127.0.0.1",
            port: walletPort,
            controlPort: controlPort,
            requestCount: await stats.requestCount,
            lastRequestAt: await stats.lastRequestAt
        )
        let databaseStatus = DatabaseStatus(
            state: .healthy,
            path: await database.path,
            sizeBytes: await database.fileSize(),
            migrationVersion: await database.migrationVersion
        )
        let publicEndpoint = lastPublicEndpoint ?? PublicEndpointStatus(state: tunnelStatus.publicHostname == nil ? .notConfigured : .waiting, reachable: false)

        let (overall, title, detail) = Self.overallState(
            config: config,
            signing: signingState,
            puregym: puregymState,
            passExists: passState != nil,
            qr: qrStatus,
            tunnel: tunnelStatus
        )

        return StatusSnapshot(
            generatedAt: Date(),
            overall: overall,
            overallTitle: title,
            overallDetail: detail,
            agent: AgentStatus(
                state: .healthy,
                pid: Int(ProcessInfo.processInfo.processIdentifier),
                startedAt: startedAt,
                version: Self.version,
                installation: installation,
                protocolVersion: AgentProtocol.version,
                inDemoMode: demoMode
            ),
            puregym: PureGymStatus(
                state: puregymState,
                accountEmail: config.accountEmail,
                memberName: config.memberName,
                homeGym: config.homeGymName,
                homeGymLocation: config.location,
                lastCheckedAt: qrState?.retrievedAt,
                lastHTTPStatus: nil,
                lastLatencyMilliseconds: nil,
                authenticationValid: tokens != nil,
                tokenExpiresAt: tokens?.expiresAt
            ),
            wallet: WalletStatus(
                state: walletState,
                serialNumber: passState?.serialNumber,
                passTypeIdentifier: passState?.passTypeIdentifier,
                revision: passState?.revision,
                lastGeneratedAt: passState?.lastGeneratedAt,
                lastPublishedAt: passState?.publishedAt,
                registrationCount: registrationCount,
                appearance: config.appearance,
                location: config.location
            ),
            signing: SigningStatus(
                state: signingState,
                passTypeIdentifier: info?.passTypeIdentifier,
                teamIdentifier: info?.teamIdentifier,
                subject: info?.commonName,
                issuer: info?.organization,
                expiresAt: info?.expiresAt,
                privateKeyAvailable: info?.hasPrivateKey ?? false,
                lastSelfTestAt: lastSigningSelfTest?.0,
                selfTestPassed: lastSigningSelfTest?.1,
                detail: lastSigningSelfTest?.2
            ),
            apns: APNsStatus(
                state: apnsState,
                lastAttemptAt: nil,
                lastAcceptedAt: nil,
                lastResultDescription: lastAPNsDescription,
                pendingCount: pending
            ),
            server: serverStatus,
            tunnel: tunnelStatus,
            publicEndpoint: publicEndpoint,
            database: databaseStatus,
            qr: qrStatus
        )
    }

    static let version = "1.0.0"

    private static func overallState(
        config: AgentConfiguration,
        signing: ServiceState,
        puregym: ServiceState,
        passExists: Bool,
        qr: QRStatus,
        tunnel: TunnelStatus
    ) -> (HealthLevel, String, String) {
        if signing == .notConfigured || signing == .unavailable {
            return (.setup, "Wallet signing needs attention", "GymPass needs a valid Apple Wallet signing certificate before it can create your pass.")
        }
        if puregym == .notConfigured {
            return (.setup, "Connect your PureGym account", "Sign in so GymPass can retrieve your access code.")
        }
        if puregym == .warning {
            return (.attention, "GymPass needs your attention", "PureGym could not be checked recently. Your saved pass remains available.")
        }
        if qr.reportedExpiryPassed {
            return (.attention, "The access code may have expired", "GymPass could not refresh before the reported expiry. It will keep trying automatically.")
        }
        if passExists && tunnel.state == .notConfigured {
            return (.attention, "Automatic updates are not set up", "Your pass is ready, but it cannot update until a public hostname is configured.")
        }
        if passExists {
            return (.healthy, "Everything is ready", "GymPass is running and your latest access code is ready for Wallet.")
        }
        return (.setup, "Ready to create your pass", "GymPass will create your Wallet pass once your account and certificate are ready.")
    }
}

extension StatusSnapshot {
    static func unavailableSnapshot() -> StatusSnapshot {
        StatusSnapshot(
            overall: .unavailable,
            overallTitle: "GymPass is starting",
            overallDetail: "The background service is not ready yet.",
            agent: AgentStatus(state: .unavailable, pid: nil, startedAt: nil, version: AgentRuntime.version, installation: .unavailable, protocolVersion: AgentProtocol.version, inDemoMode: false),
            puregym: PureGymStatus(state: .inactive),
            wallet: WalletStatus(state: .inactive),
            signing: SigningStatus(state: .inactive),
            apns: APNsStatus(state: .inactive),
            server: ServerStatus(state: .inactive),
            tunnel: TunnelStatus(state: .inactive),
            publicEndpoint: PublicEndpointStatus(state: .inactive),
            database: DatabaseStatus(state: .inactive, path: "-", sizeBytes: 0, migrationVersion: "-"),
            qr: QRStatus(present: false)
        )
    }
}
