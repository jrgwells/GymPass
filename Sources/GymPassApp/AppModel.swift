import Foundation
import Observation
import GymPassCore
import GymPassShared

enum SidebarDestination: String, CaseIterable, Identifiable {
    case dashboard, wallet, activity, diagnostics
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .wallet: "Wallet"
        case .activity: "Activity"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .wallet: "wallet.pass"
        case .activity: "clock.arrow.circlepath"
        case .diagnostics: "stethoscope"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var status: StatusSnapshot?
    var activity: [ActivityEvent] = []
    var agentReachable = false
    var agentInstallation: AgentInstallationStatus = .notInstalled
    var selectedDestination: SidebarDestination? = .dashboard
    var showingOnboarding = false
    var lastProblem: String?
    var banner: BannerMessage?
    var busy: Bool = false
    var lastRefreshSucceeded: Date?
    var preview: PassPreview?

    private var pollTask: Task<Void, Never>?
    private let installer: AgentInstaller

    struct BannerMessage: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    init() {
        installer = AgentInstaller(executablePath: Self.agentExecutablePath())
    }

    static func agentExecutablePath() -> String {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        return executable.deletingLastPathComponent().appendingPathComponent("GymPassAgent").path
    }

    var needsOnboarding: Bool {
        guard let status else { return false }
        if status.puregym.accountEmail == nil { return true }
        if status.signing.state == .notConfigured { return true }
        return false
    }

    var menuBarSymbol: String {
        guard agentReachable, let status else { return "wallet.pass" }
        switch status.overall {
        case .healthy: return "checkmark.circle"
        case .attention: return "exclamationmark.circle"
        case .setup: return "wallet.pass"
        case .unavailable: return "xmark.circle"
        }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshAll() async {
        agentInstallation = await installer.status()
        guard let client = AgentClient.discover() else {
            agentReachable = false
            return
        }
        do {
            async let status = client.status()
            async let activity = client.activity(limit: 100)
            self.status = try await status
            self.activity = try await activity
            agentReachable = true
            lastRefreshSucceeded = Date()
        } catch {
            agentReachable = false
        }
    }

    @discardableResult
    func send(_ request: AgentRequest) async -> AgentResponse {
        busy = true
        defer { busy = false }
        guard let client = AgentClient.discover() else {
            lastProblem = "The background service is not running."
            banner = BannerMessage(text: "The background service is not running.", isError: true)
            return .failure(AgentErrorPayload(code: "agent_unreachable", message: "The background service is not running."))
        }
        do {
            let response = try await client.send(request)
            apply(response)
            return response
        } catch {
            lastProblem = "GymPass could not reach the background service."
            return .failure(AgentErrorPayload(code: "agent_unreachable", message: "GymPass could not reach the background service."))
        }
    }

    private func apply(_ response: AgentResponse) {
        switch response {
        case .status(let snapshot):
            status = snapshot
        case .activity(let events):
            activity = events
        case .failure(let payload):
            banner = BannerMessage(text: payload.message, isError: true)
        case .text(let message):
            banner = BannerMessage(text: message, isError: false)
        case .installLink(let link):
            banner = BannerMessage(text: "Installation link ready for \(link.expiresAt.formatted(date: .omitted, time: .shortened)).", isError: false)
        case .passPreview(let preview):
            self.preview = preview
        case .diagnostic:
            break
        case .ok:
            break
        }
    }

    // MARK: - Convenience actions

    func refreshQR() async {
        await send(.refreshQR)
    }

    func regeneratePass() async {
        await send(.regeneratePass)
    }

    func testServices() async {
        await send(.runDiagnostic(.full))
    }

    func installAgent() async {
        do {
            try await installer.install()
            banner = BannerMessage(text: "The background service is starting.", isError: false)
        } catch {
            banner = BannerMessage(text: (error as? GymPassError)?.userMessage ?? "The background service could not be installed.", isError: true)
        }
        await refreshAll()
    }

    func uninstallAgent() async {
        try? await installer.uninstall()
        await refreshAll()
    }

    func restartAgent() async {
        await installer.restart()
    }

    func openApprovalSettings() {
        installer.openApprovalSettings()
    }

    func createInstallLink() async -> InstallLink? {
        let response = await send(.createInstallLink)
        if case .installLink(let link) = response { return link }
        return nil
    }
}
