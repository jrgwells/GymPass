import Foundation
import Observation
import SwiftUI
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
    enum BusyAction: Hashable {
        case refresh, regenerate, diagnose, install, preview
    }

    enum SettingsTab: String, Hashable {
        case general, puregym, wallet, connectivity, advanced
    }

    var status: StatusSnapshot?
    var activity: [ActivityEvent] = []
    var agentReachable = false
    var agentInstallation: AgentInstallationStatus = .notInstalled
    var selectedDestination: SidebarDestination? = .dashboard
    var showingOnboarding = false
    var onboardingStartStep = 0
    var hasAutoPresentedOnboarding = false
    var settingsTab: SettingsTab = .general
    var banner: BannerMessage?
    var lastRefreshSucceeded: Date?
    var preview: PassPreview?

    private var inFlight: Set<BusyAction> = []
    private var pollTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var lastPreviewRevision: Int?
    private let installer: AgentInstaller

    struct BannerMessage: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    init() {
        installer = AgentInstaller(executablePath: Self.agentExecutablePath())
        applyLaunchOverrides()
    }

    /// Developer/UI-testing affordances. These only act when the corresponding
    /// environment variables are set (see docs/development.md) and never alter
    /// normal launch behaviour.
    private func applyLaunchOverrides() {
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["GYMPASS_START_DESTINATION"],
           let destination = SidebarDestination(rawValue: raw) {
            selectedDestination = destination
        }
        if environment["GYMPASS_SHOW_ONBOARDING"] == "1" {
            showingOnboarding = true
            hasAutoPresentedOnboarding = true
        }
        if let raw = environment["GYMPASS_SETTINGS_TAB"], let tab = SettingsTab(rawValue: raw) {
            settingsTab = tab
        }
    }

    static var initialWindowSize: CGSize {
        let environment = ProcessInfo.processInfo.environment
        let width = environment["GYMPASS_WINDOW_WIDTH"].flatMap(Double.init) ?? 960
        let height = environment["GYMPASS_WINDOW_HEIGHT"].flatMap(Double.init) ?? 680
        let clampedWidth = min(max(width, 760), 1600)
        let clampedHeight = min(max(height, 560), 1100)
        return CGSize(width: clampedWidth, height: clampedHeight)
    }

    /// The declared minimum window size. `GYMPASS_WINDOW_WIDTH`/`HEIGHT` also
    /// raise the minimum so UI-testing captures can force a wide window.
    static var minimumWindowSize: CGSize {
        let environment = ProcessInfo.processInfo.environment
        let width = environment["GYMPASS_WINDOW_WIDTH"].flatMap(Double.init) ?? 760
        let height = environment["GYMPASS_WINDOW_HEIGHT"].flatMap(Double.init) ?? 560
        return CGSize(width: min(max(width, 760), 1600), height: min(max(height, 560), 1100))
    }

    static func agentExecutablePath() -> String {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        return executable.deletingLastPathComponent().appendingPathComponent("GymPassAgent").path
    }

    // MARK: - Derived state

    var needsOnboarding: Bool {
        guard let status else { return false }
        if status.puregym.accountEmail == nil { return true }
        if status.signing.state == .notConfigured { return true }
        return false
    }

    func isBusy(_ action: BusyAction) -> Bool { inFlight.contains(action) }
    var isRefreshing: Bool { isBusy(.refresh) }
    var isRegenerating: Bool { isBusy(.regenerate) }
    var isDiagnosing: Bool { isBusy(.diagnose) }
    var isInstalling: Bool { isBusy(.install) }

    var menuBarSymbol: String {
        guard agentReachable, let status else { return "wallet.pass" }
        switch status.overall {
        case .healthy: return "checkmark.circle"
        case .attention: return "exclamationmark.circle"
        case .setup: return "wallet.pass"
        case .unavailable: return "xmark.circle"
        }
    }

    // MARK: - Polling

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
            let snapshot = try await status
            self.activity = try await activity
            self.status = snapshot
            agentReachable = true
            lastRefreshSucceeded = Date()
            if let revision = snapshot.wallet.revision, revision != lastPreviewRevision {
                await requestPreview()
            }
        } catch {
            agentReachable = false
        }
    }

    // MARK: - Requests

    @discardableResult
    func send(_ request: AgentRequest, action: BusyAction? = nil, silentOnFailure: Bool = false) async -> AgentResponse {
        if let action { inFlight.insert(action) }
        defer { if let action { inFlight.remove(action) } }

        guard let client = AgentClient.discover() else {
            if !silentOnFailure {
                showBanner("The background service is not running.", isError: true)
            }
            return .failure(AgentErrorPayload(code: "agent_unreachable", message: "The background service is not running."))
        }
        do {
            let response = try await client.send(request)
            apply(response, silentOnFailure: silentOnFailure)
            return response
        } catch {
            if !silentOnFailure {
                showBanner("GymPass could not reach the background service.", isError: true)
            }
            return .failure(AgentErrorPayload(code: "agent_unreachable", message: "GymPass could not reach the background service."))
        }
    }

    private func apply(_ response: AgentResponse, silentOnFailure: Bool) {
        switch response {
        case .status(let snapshot):
            status = snapshot
            if let revision = snapshot.wallet.revision, revision != lastPreviewRevision {
                Task { await requestPreview() }
            }
        case .activity(let events):
            activity = events
        case .failure(let payload):
            if !silentOnFailure { showBanner(payload.message, isError: true) }
        case .text(let message):
            showBanner(message, isError: false)
        case .installLink:
            break // The caller presents the installation sheet.
        case .passPreview(let preview):
            self.preview = preview
            lastPreviewRevision = preview.revision
        case .diagnostic:
            break
        case .ok:
            break
        }
    }

    func requestPreview() async {
        inFlight.insert(.preview)
        defer { inFlight.remove(.preview) }
        guard let client = AgentClient.discover() else { return }
        guard let response = try? await client.send(.passPreview),
              case .passPreview(let preview) = response else { return }
        self.preview = preview
        lastPreviewRevision = preview.revision
    }

    // MARK: - Banner

    func showBanner(_ text: String, isError: Bool) {
        withAnimation(.easeInOut(duration: 0.25)) {
            banner = BannerMessage(text: text, isError: isError)
        }
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        bannerTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            banner = nil
        }
    }

    // MARK: - Convenience actions

    func refreshQR() async {
        await send(.refreshQR, action: .refresh)
        await requestPreview()
    }

    func regeneratePass() async {
        await send(.regeneratePass, action: .regenerate)
        await requestPreview()
    }

    func testServices() async {
        let response = await send(.runDiagnostic(.full), action: .diagnose, silentOnFailure: true)
        if case .diagnostic(let report) = response {
            showBanner(
                report.overall == .healthy ? "All services responded normally." : "Some services need attention. See Diagnostics.",
                isError: report.overall != .healthy
            )
        }
    }

    func installAgent() async {
        inFlight.insert(.install)
        defer { inFlight.remove(.install) }
        do {
            try await installer.install()
            showBanner("The background service is starting.", isError: false)
        } catch {
            showBanner((error as? GymPassError)?.userMessage ?? "The background service could not be installed.", isError: true)
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
