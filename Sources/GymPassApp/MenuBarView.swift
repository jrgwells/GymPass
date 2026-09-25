import SwiftUI
import AppKit
import GymPassShared

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let status = model.status
        Text(summaryTitle(status))
            .font(.headline)

        if let status, status.overall != .healthy {
            Text(status.overallDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        if let status {
            Text("Pass updated: \(status.wallet.lastPublishedAt.map { DurationFormatter.minutesAgo($0) } ?? "not yet")")
            Text("PureGym: \(status.puregym.state == .healthy ? "Connected" : status.puregym.state.phrase)")
            Text("Automatic updates: \(status.tunnel.state == .healthy ? "Running" : status.tunnel.state.phrase)")
        } else if model.agentReachable {
            Text("Checking…")
        } else {
            Text("Background service not running")
        }

        Divider()

        Button("Refresh Now") { Task { await model.refreshQR() } }
            .disabled(!model.agentReachable)

        Button("Open GymPass") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("Settings…") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }

        Divider()

        Button("Install Background Service") { Task { await model.installAgent() } }
            .disabled(model.agentReachable)

        Button("Quit GymPass") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func summaryTitle(_ status: StatusSnapshot?) -> String {
        guard model.agentReachable, let status else { return "GymPass — starting" }
        switch status.overall {
        case .healthy: return "GymPass — everything is ready"
        case .attention: return "GymPass — needs attention"
        case .setup: return "GymPass — setup needed"
        case .unavailable: return "GymPass — unavailable"
        }
    }
}
