import Foundation
import GymPassCore
import GymPassShared

extension AgentRuntime {
    // MARK: - Request handling

    public func handle(_ request: AgentRequest) async -> AgentResponse {
        switch request {
        case .ping:
            return .ok
        case .getStatus:
            return .status(await statusSnapshot())
        case .refreshQR, .regeneratePass:
            _ = await engine?.refresh(trigger: .manual)
            return .status(await statusSnapshot())
        case .runDiagnostic(let kind):
            return .diagnostic(await runDiagnostic(kind))
        case .exportDiagnostics:
            return .diagnostic(await runDiagnostic(.full))
        case .setPureGymCredentials(let email, let pin):
            return await setCredentials(email: email, pin: pin)
        case .connectPureGym:
            return await connectPureGym()
        case .disconnectPureGym:
            return await disconnectPureGym()
        case .importSigningIdentity(let p12, let password):
            return await importSigningIdentity(p12: p12, password: password)
        case .clearSigningIdentity:
            return await clearSigningIdentity()
        case .configureTunnel(let tunnelConfiguration):
            return await configureTunnel(tunnelConfiguration)
        case .setTunnelToken(let token):
            return await setTunnelToken(token)
        case .restartTunnel:
            await restartTunnel()
            return .status(await statusSnapshot())
        case .testTunnel:
            return await testTunnel()
        case .testAPNs:
            return await testAPNs()
        case .updateAppearance(let appearance):
            config.appearance = appearance
            await saveConfig()
            _ = await engine?.refresh(trigger: .manual)
            return .status(await statusSnapshot())
        case .updateLocation(let location):
            config.location = location
            await saveConfig()
            _ = await engine?.refresh(trigger: .manual)
            return .status(await statusSnapshot())
        case .setRefreshPolicy(let policy):
            config.policy = policy
            await saveConfig()
            startSchedulerLoopRestart()
            return .status(await statusSnapshot())
        case .setPreferences(let preferences):
            config.preferences = preferences
            await saveConfig()
            await updatePowerAssertion()
            return .status(await statusSnapshot())
        case .createInstallLink:
            return await createInstallLink()
        case .resetRegistrations:
            try? await database.deleteAllRegistrations()
            return .status(await statusSnapshot())
        case .resetPass:
            try? await database.deletePassState()
            _ = await engine?.refresh(trigger: .manual)
            return .status(await statusSnapshot())
        case .listActivity(let limit):
            return .activity(await activity.recent(limit: limit))
        case .passPreview:
            return await passPreview()
        }
    }

    private func passPreview() async -> AgentResponse {
        guard let qrState = try? await database.qrState(),
              let ciphertext = qrState.qrCiphertext,
              let code = try? crypto.openString(ciphertext) else {
            return .failure(AgentErrorPayload(code: "no_qr", message: "No access code has been retrieved yet."))
        }
        guard let identity = await currentPassIdentity(),
              let passState = try? await database.passState(serialNumber: identity.serialNumber) else {
            return .failure(AgentErrorPayload(code: "no_pass", message: "No Wallet pass has been generated yet."))
        }
        let preview = PassPreview(
            qrPayload: code,
            serialNumber: identity.serialNumber,
            passTypeIdentifier: identity.passTypeIdentifier,
            memberName: config.appearance.memberName,
            gymLabel: config.appearance.gymLabel,
            appearance: config.appearance,
            revision: passState.revision,
            updatedAt: passState.publishedAt
        )
        return .passPreview(preview)
    }

    // MARK: - PureGym

    private func setCredentials(email: String, pin: String) async -> AgentResponse {
        do {
            try await secrets.set(email, for: KeychainStore.Key.puregymEmail.rawValue)
            try await secrets.set(pin, for: KeychainStore.Key.puregymPIN.rawValue)
            let tokens = try await puregym.authenticate(email: email, pin: pin)
            try await persist(tokens: tokens)
            config.accountEmail = email
            await refreshAccountMetadata()
            await saveConfig()
            _ = await engine?.refresh(trigger: .authRecovery)
            return .status(await statusSnapshot())
        } catch {
            return Self.failure(error)
        }
    }

    private func connectPureGym() async -> AgentResponse {
        do {
            guard let email = try await secrets.getString(KeychainStore.Key.puregymEmail.rawValue),
                  let pin = try await secrets.getString(KeychainStore.Key.puregymPIN.rawValue) else {
                throw GymPassError.notConfigured("PureGym account")
            }
            let tokens = try await puregym.authenticate(email: email, pin: pin)
            try await persist(tokens: tokens)
            config.accountEmail = email
            await refreshAccountMetadata()
            await saveConfig()
            _ = await engine?.refresh(trigger: .authRecovery)
            return .status(await statusSnapshot())
        } catch {
            return Self.failure(error)
        }
    }

    private func disconnectPureGym() async -> AgentResponse {
        try? await secrets.delete(KeychainStore.Key.puregymEmail.rawValue)
        try? await secrets.delete(KeychainStore.Key.puregymPIN.rawValue)
        try? await secrets.delete(KeychainStore.Key.puregymTokens.rawValue)
        await puregym.setTokens(nil)
        config.accountEmail = nil
        config.memberName = nil
        await saveConfig()
        return .status(await statusSnapshot())
    }

    private func persist(tokens: PureGymTokens) async throws {
        let data = try JSONEncoder().encode(tokens)
        try await secrets.set(data, for: KeychainStore.Key.puregymTokens.rawValue)
        await puregym.setTokens(tokens)
    }

    private func refreshAccountMetadata() async {
        if let member = try? await puregym.fetchMember(), let name = member.name {
            config.memberName = name
        }
        if let gyms = try? await puregym.fetchGyms() {
            var homeGymID: Int?
            if let member = try? await puregym.fetchMember() {
                homeGymID = member.homeGymID
                if config.memberName == nil { config.memberName = member.name }
                if config.homeGymName == nil { config.homeGymName = member.homeGymName }
            }
            if let homeGymID, let gym = gyms.first(where: { $0.id == homeGymID }) {
                config.homeGymName = gym.name
                if config.location == nil, let latitude = gym.latitude, let longitude = gym.longitude {
                    config.location = PassLocation(label: gym.name, latitude: latitude, longitude: longitude, relevantText: gym.name)
                }
            }
        }
    }

    // MARK: - Signing

    private func importSigningIdentity(p12: Data, password: String) async -> AgentResponse {
        do {
            let info = try await signingStore.importPKCS12(p12, password: password)
            guard let passType = info.passTypeIdentifier, let team = info.teamIdentifier else {
                throw GymPassError.signingFailed("The certificate is not a Wallet Pass Type ID certificate.")
            }
            let serial = try await walletService.passIdentity()?.serialNumber ?? SecureRandom.hex(8)
            try await walletService.setPassIdentity(passTypeIdentifier: passType, serialNumber: serial, teamIdentifier: team)

            let selfTest = await PassSigner(signingStore: signingStore).selfTest()
            lastSigningSelfTest = (Date(), selfTest.passed, selfTest.detail)
            await saveConfig()
            if selfTest.passed {
                _ = await engine?.refresh(trigger: .manual)
                return .status(await statusSnapshot())
            }
            return .failure(AgentErrorPayload(code: "signing_self_test_failed", message: selfTest.detail))
        } catch {
            return Self.failure(error)
        }
    }

    private func clearSigningIdentity() async -> AgentResponse {
        try? await signingStore.clear()
        lastSigningSelfTest = nil
        return .status(await statusSnapshot())
    }

    // MARK: - Tunnel

    private func configureTunnel(_ tunnelConfiguration: TunnelConfiguration) async -> AgentResponse {
        var updated = tunnelConfiguration
        updated.hasStoredCredentials = config.tunnel.hasStoredCredentials
        config.tunnel = updated
        await saveConfig()
        await restartTunnel()
        return .status(await statusSnapshot())
    }

    private func setTunnelToken(_ token: String) async -> AgentResponse {
        do {
            try await secrets.set(token, for: KeychainStore.Key.tunnelCredentials.rawValue)
            config.tunnel.hasStoredCredentials = true
            await saveConfig()
            return .status(await statusSnapshot())
        } catch {
            return Self.failure(error)
        }
    }

    private func testTunnel() async -> AgentResponse {
        guard let tunnel else {
            return .failure(AgentErrorPayload(code: "not_configured", message: "Automatic updates are not configured."))
        }
        let status = await tunnel.healthCheck()
        lastPublicEndpoint = status
        return .text(status.reachable ? "Automatic updates are reachable." : (status.detail ?? "Automatic updates are not reachable."))
    }

    // MARK: - APNs

    private func testAPNs() async -> AgentResponse {
        if demoMode {
            lastAPNsDescription = "Demo mode: Apple Push is simulated."
            return .text("Apple Wallet notifications are simulated in demo mode.")
        }
        guard let identity = try? await signingStore.info() else {
            return .failure(AgentErrorPayload(code: "signing_unavailable", message: "A signing certificate is required before notifications can be tested."))
        }
        guard let passType = identity.passTypeIdentifier,
              let serial = try? await walletService.passIdentity()?.serialNumber else {
            return .failure(AgentErrorPayload(code: "not_configured", message: "Import a signing certificate and create a pass first."))
        }
        let registrations = (try? await database.registrations(forSerial: serial, passTypeIdentifier: passType)) ?? []
        guard let registration = registrations.first else {
            return .failure(AgentErrorPayload(code: "no_registrations", message: "No Wallet registrations yet. Add the pass to Wallet first."))
        }
        let result = await apns.send(pushToken: registration.pushToken, policy: WalletAPNsPolicy(topic: passType))
        switch result {
        case .accepted:
            lastAPNsDescription = "Apple accepted the update notification."
            return .text("Apple accepted the update notification.")
        case .invalidToken(let reason):
            lastAPNsDescription = "The push token was rejected: \(reason ?? "unknown")."
            return .text("That Wallet registration is no longer valid; it will re-register automatically.")
        case .transient(let status, let reason):
            lastAPNsDescription = "Apple Push was temporarily unavailable (\(status))."
            return .failure(AgentErrorPayload(code: "apns_transient", message: "Apple Push is temporarily unavailable.", detail: reason))
        case .topicMismatch(let reason):
            lastAPNsDescription = "The pass type does not match the certificate."
            return .failure(AgentErrorPayload(code: "apns_topic_mismatch", message: "The pass type does not match the signing certificate.", detail: reason))
        case .rejected(let status, let reason):
            lastAPNsDescription = "Apple Push rejected the notification (\(status))."
            return .failure(AgentErrorPayload(code: "apns_rejected", message: "Apple Push rejected the notification.", detail: reason))
        }
    }

    // MARK: - Installation

    private func createInstallLink() async -> AgentResponse {
        guard let hostname = config.tunnel.publicHostname, !hostname.isEmpty else {
            return .failure(AgentErrorPayload(code: "not_configured", message: "Configure a public hostname before creating an installation link."))
        }
        do {
            let link = try await walletService.createInstallLink(hostname: hostname)
            return .installLink(link)
        } catch {
            return Self.failure(error)
        }
    }

    // MARK: - Diagnostics

    func runDiagnostic(_ kind: DiagnosticKind) async -> DiagnosticReport {
        var checks: [DiagnosticCheck] = []

        func wants(_ target: DiagnosticKind) -> Bool { kind == .full || kind == target }

        if wants(.agent) {
            let installation = await installer.status()
            checks.append(DiagnosticCheck(name: "Background Agent", state: installation == .running ? .healthy : .warning, summary: installation.phrase, detail: "PID \(ProcessInfo.processInfo.processIdentifier)"))
        }
        if wants(.database) {
            let size = await database.fileSize()
            let version = await database.migrationVersion
            let path = await database.path
            checks.append(DiagnosticCheck(name: "Database", state: .healthy, summary: "\(size) bytes", detail: "Schema \(version) at \(path)"))
        }
        if wants(.signing) {
            if let info = try? await signingStore.info() {
                let selfTest = await PassSigner(signingStore: signingStore).selfTest()
                lastSigningSelfTest = (Date(), selfTest.passed, selfTest.detail)
                checks.append(DiagnosticCheck(name: "Wallet Signing", state: selfTest.passed ? .healthy : .unavailable, summary: selfTest.passed ? "Signed and verified" : "Failed", detail: info.expiresAt.map { "Certificate expires \(GymPassDate.iso8601($0))" }))
            } else {
                checks.append(DiagnosticCheck(name: "Wallet Signing", state: .notConfigured, summary: "No certificate imported"))
            }
        }
        if wants(.puregym) {
            if await puregym.currentTokens() != nil {
                let start = Date()
                do {
                    _ = try await puregym.fetchGyms()
                    let latency = Int(Date().timeIntervalSince(start) * 1000)
                    checks.append(DiagnosticCheck(name: "PureGym", state: .healthy, summary: "Authenticated", detail: "Latency \(latency) ms", durationMilliseconds: latency))
                } catch {
                    checks.append(DiagnosticCheck(name: "PureGym", state: .warning, summary: "Request failed", detail: (error as? GymPassError)?.userMessage))
                }
            } else {
                checks.append(DiagnosticCheck(name: "PureGym", state: .notConfigured, summary: "Not signed in"))
            }
        }
        if wants(.localServer) {
            let reachable = await pingLocalServer()
            checks.append(DiagnosticCheck(name: "Local Server", state: reachable ? .healthy : .unavailable, summary: reachable ? "127.0.0.1:\(walletPort)" : "Not responding"))
        }
        if wants(.publicEndpoint) {
            if let tunnel {
                let status = await tunnel.healthCheck()
                lastPublicEndpoint = status
                checks.append(DiagnosticCheck(name: "Remote Access", state: status.state, summary: status.reachable ? "Reachable" : (status.detail ?? "Unreachable"), detail: status.latencyMilliseconds.map { "Latency \($0) ms" }))
            } else {
                checks.append(DiagnosticCheck(name: "Remote Access", state: .notConfigured, summary: "No tunnel configured"))
            }
        }
        if wants(.apns) {
            let pending = await dispatcher.pendingCount()
            checks.append(DiagnosticCheck(name: "Apple Push", state: demoMode ? .healthy : (pending > 0 ? .working : .healthy), summary: demoMode ? "Simulated" : "\(pending) pending", detail: lastAPNsDescription))
        }

        let overall: ServiceState = checks.contains { $0.state == .unavailable } ? .unavailable : (checks.contains { $0.state == .warning } ? .warning : .healthy)
        return DiagnosticReport(overall: overall, checks: checks)
    }

    private func pingLocalServer() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(walletPort)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Helpers

    static func failure(_ error: Error) -> AgentResponse {
        if let gymPassError = error as? GymPassError {
            return .failure(gymPassError.payload)
        }
        return .failure(AgentErrorPayload(code: "internal_error", message: "Something went wrong.", detail: Redactor.redact(String(describing: error))))
    }
}
