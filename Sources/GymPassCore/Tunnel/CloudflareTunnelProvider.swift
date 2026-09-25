import Foundation
import GymPassShared

/// Supervises a `cloudflared` child process. The agent is the single owner.
public actor CloudflareTunnelProvider: PublicIngressProvider {
    public nonisolated let kind: TunnelProviderKind

    private let configuration: TunnelConfiguration
    private let tokenProvider: @Sendable () async -> String?
    private let walletPort: Int
    private var process: Process?
    private var outputTask: Task<Void, Never>?
    private var connected = false
    private var discoveredHostname: String?
    private var lastError: String?
    private var lastConnectedAt: Date?
    private var binaryURL: URL?
    private var restartCount = 0

    public init(
        configuration: TunnelConfiguration,
        walletPort: Int,
        tokenProvider: @escaping @Sendable () async -> String?
    ) {
        self.kind = configuration.provider
        self.configuration = configuration
        self.walletPort = walletPort
        self.tokenProvider = tokenProvider
    }

    public func start() async throws {
        if process?.isRunning == true { return }
        guard let binary = TunnelBinaryLocator.locate() else {
            lastError = "cloudflared is not installed"
            throw GymPassError.notConfigured("cloudflared")
        }
        binaryURL = binary

        let process = Process()
        process.executableURL = binary
        switch configuration.provider {
        case .cloudflareNamed:
            guard let token = await tokenProvider(), !token.isEmpty else {
                lastError = "No tunnel credentials configured"
                throw GymPassError.notConfigured("Cloudflare Tunnel credentials")
            }
            process.arguments = ["tunnel", "--no-autoupdate", "run"]
            var environment = ProcessInfo.processInfo.environment
            environment["TUNNEL_TOKEN"] = token
            process.environment = environment
        case .cloudflareQuick:
            process.arguments = [
                "tunnel", "--no-autoupdate", "--url",
                "http://127.0.0.1:\(walletPort)",
            ]
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] proc in
            Task { await self?.handleTermination(exitCode: proc.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            lastError = Redactor.redact(String(describing: error))
            throw GymPassError.internalError("Could not start cloudflared")
        }
        self.process = process
        self.lastError = nil
        Log.tunnel.info("cloudflared started (\(self.configuration.provider.rawValue, privacy: .public))")

        let collector = ProcessOutputCollector(pipe.fileHandleForReading)
        outputTask = Task { [weak self] in
            do {
                for try await line in collector.handle.bytes.lines {
                    await self?.handleOutput(line)
                }
            } catch {
                // Stream ended when the process exited.
            }
        }
    }

    public func stop() async {
        outputTask?.cancel()
        outputTask = nil
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        connected = false
    }

    public func status() async -> TunnelStatus {
        let binary = TunnelBinaryLocator.locate() != nil
        let state: ServiceState
        if binary == false {
            state = .notConfigured
        } else if connected {
            state = .healthy
        } else if configuration.provider == .cloudflareNamed, configuration.publicHostname == nil {
            state = .notConfigured
        } else if process?.isRunning == true {
            state = .working
        } else {
            state = .unavailable
        }
        let hostname = configuration.publicHostname ?? discoveredHostname
        return TunnelStatus(
            state: state,
            provider: configuration.provider,
            publicHostname: hostname,
            lastConnectedAt: lastConnectedAt,
            lastError: lastError,
            binaryAvailable: binary,
            ephemeral: configuration.provider == .cloudflareQuick
        )
    }

    public func healthCheck() async -> PublicEndpointStatus {
        guard let hostname = configuration.publicHostname ?? discoveredHostname else {
            return PublicEndpointStatus(state: .notConfigured, reachable: false, detail: "No public hostname configured")
        }
        guard let url = URL(string: "https://\(hostname)/health") else {
            return PublicEndpointStatus(state: .unavailable, reachable: false, detail: "Invalid hostname")
        }
        let start = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return PublicEndpointStatus(state: .warning, reachable: false, detail: "Unexpected response")
            }
            let healthOK = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String == "ok"
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            return PublicEndpointStatus(
                state: healthOK ? .healthy : .warning,
                reachable: healthOK,
                latencyMilliseconds: latency,
                lastCheckedAt: Date(),
                detail: healthOK ? nil : "Health response was unexpected"
            )
        } catch {
            return PublicEndpointStatus(state: .unavailable, reachable: false, lastCheckedAt: Date(), detail: Redactor.redact(String(describing: error)))
        }
    }

    // MARK: - Output handling

    private func handleOutput(_ line: String) {
        let redacted = Redactor.redact(line)
        if let hostname = Self.extractHostname(from: line) {
            discoveredHostname = hostname
        }
        if line.contains("Registered tunnel connection") || line.contains("Connection registered") {
            connected = true
            lastConnectedAt = Date()
        }
        Log.tunnel.debug("\(redacted, privacy: .public)")
    }

    private func handleTermination(exitCode: Int32) {
        connected = false
        lastError = "cloudflared exited (code \(exitCode))"
        Log.tunnel.error("cloudflared exited with code \(exitCode, privacy: .public)")
    }

    private static func extractHostname(from line: String) -> String? {
        guard let range = line.range(of: "https://") else { return nil }
        let remainder = line[range.lowerBound...]
        let token = remainder.prefix { !$0.isWhitespace && $0 != "/" }
        let hostname = String(token.dropFirst("https://".count))
        guard hostname.contains(".") else { return nil }
        return hostname
    }
}
