import SwiftUI
import GymPassShared

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var report: DiagnosticReport?
    @State private var running = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                if let report {
                    GroupCard(title: "Overall Health") {
                        StatusLabel(state: report.overall, text: report.overall.phrase)
                            .font(.headline)
                    }
                    GroupCard(title: "Diagnostic Results") {
                        ForEach(report.checks) { check in
                            VStack(alignment: .leading, spacing: 2) {
                                StatusLabel(state: check.state, text: "\(check.name): \(check.summary)")
                                if let detail = check.detail {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    GroupCard(title: "Overall Health") {
                        StatusLabel(state: model.status?.overall == .healthy ? .healthy : (model.status?.overall == .attention ? .warning : .inactive), text: model.status?.overallTitle ?? "Unknown")
                            .font(.headline)
                    }
                }

                GroupCard(title: "System") {
                    MetricRow(label: "Background agent", value: model.status?.agent.installation.phrase ?? "—")
                    MetricRow(label: "PID", value: model.status?.agent.pid.map(String.init) ?? "—")
                    MetricRow(label: "Started", value: model.status?.agent.startedAt.map { DurationFormatter.minutesAgo($0).replacingOccurrences(of: " ago", with: "") } ?? "—")
                    MetricRow(label: "Demo mode", value: (model.status?.agent.inDemoMode ?? false) ? "Yes" : "No")
                }
                GroupCard(title: "PureGym") {
                    MetricRow(label: "Authentication", value: (model.status?.puregym.authenticationValid ?? false) ? "Valid" : "Not signed in")
                    MetricRow(label: "Last request", value: model.status?.puregym.lastCheckedAt.map { DurationFormatter.minutesAgo($0) } ?? "—")
                    MetricRow(label: "Token expiry", value: model.status?.puregym.tokenExpiresAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                }
                GroupCard(title: "Wallet") {
                    MetricRow(label: "Signing", value: model.status?.signing.state.phrase ?? "—")
                    MetricRow(label: "Pass type", value: model.status?.signing.passTypeIdentifier ?? "—")
                    MetricRow(label: "Certificate expiry", value: model.status?.signing.expiresAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                    MetricRow(label: "Registered devices", value: "\(model.status?.wallet.registrationCount ?? 0)")
                    MetricRow(label: "Revision", value: model.status?.wallet.revision.map(String.init) ?? "—")
                }
                GroupCard(title: "Apple Push") {
                    MetricRow(label: "Pending notifications", value: "\(model.status?.apns.pendingCount ?? 0)")
                    MetricRow(label: "Last result", value: model.status?.apns.lastResultDescription ?? "—")
                }
                GroupCard(title: "Remote Access") {
                    MetricRow(label: "Provider", value: model.status?.tunnel.provider.displayName ?? "—")
                    MetricRow(label: "Hostname", value: model.status?.tunnel.publicHostname ?? "Not configured")
                    MetricRow(label: "Endpoint", value: model.status?.publicEndpoint.reachable == true ? "Reachable" : "Not verified")
                }
                GroupCard(title: "Database") {
                    MetricRow(label: "Location", value: model.status?.database.path ?? "—")
                    MetricRow(label: "Schema", value: model.status?.database.migrationVersion ?? "—")
                    MetricRow(label: "Size", value: "\(model.status?.database.sizeBytes ?? 0) bytes")
                }

                actions
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Diagnostics")
    }

    private var actions: some View {
        GroupCard(title: "Actions") {
            HStack(spacing: Spacing.m) {
                PrimaryActionButton(title: "Run Full Diagnostic", systemImage: "stethoscope", isBusy: running || model.busy) {
                    Task { await run(.full) }
                }
                Button("Test PureGym") { Task { await run(.puregym) } }
                Button("Test Signing") { Task { await run(.signing) } }
                Button("Test Apple Push") { Task { await run(.apns) } }
                Button("Test Remote Access") { Task { await run(.publicEndpoint) } }
            }
            HStack(spacing: Spacing.m) {
                Button("Restart Background Service") { Task { await model.restartAgent() } }
                Button("Export Diagnostics") {
                    Task {
                        let response = await model.send(.exportDiagnostics)
                        if case .diagnostic(let report) = response {
                            export(report)
                        }
                    }
                }
            }
        }
    }

    private func run(_ kind: DiagnosticKind) async {
        running = true
        defer { running = false }
        let response = await model.send(.runDiagnostic(kind))
        if case .diagnostic(let report) = response {
            self.report = report
        }
    }

    private func export(_ report: DiagnosticReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gympass-diagnostics.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
