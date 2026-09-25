import SwiftUI
import GymPassShared

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var installLink: InstallLink?
    @State private var showingInstall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                overallHeader
                passHero
                HStack(alignment: .top, spacing: Spacing.section) {
                    membership
                    services
                }
                actions
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("GymPass")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refreshQR() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh the access code (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.busy)
            }
        }
        .task { await model.send(.passPreview) }
        .sheet(isPresented: $showingInstall) {
            if let installLink {
                InstallPassSheet(link: installLink)
            }
        }
    }

    private var overallHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Image(systemName: overallSymbol)
                    .foregroundStyle(overallColor)
                Text(model.status?.overallTitle ?? (model.agentReachable ? "Checking…" : "Background service not running"))
                    .font(.title2.weight(.semibold))
            }
            Text(model.status?.overallDetail ?? "GymPass is starting up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.agentReachable {
                PrimaryActionButton(title: "Install Background Service", systemImage: "gearshape") {
                    Task { await model.installAgent() }
                }
                .padding(.top, Spacing.s)
            } else if let status = model.status, status.overall == .setup {
                if status.signing.state == .notConfigured {
                    Button("Open Setup…") { model.showingOnboarding = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                } else if status.puregym.accountEmail == nil {
                    Button("Connect PureGym…") { model.showingOnboarding = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            }
        }
    }

    private var passHero: some View {
        HStack {
            Spacer()
            PassPreviewView(
                appearance: model.preview?.appearance ?? model.status?.wallet.appearance ?? .default,
                qrPayload: model.preview?.qrPayload,
                memberName: model.preview?.memberName ?? model.status?.puregym.memberName,
                updatedAt: model.status?.wallet.lastPublishedAt
            )
            .contextMenu {
                Button("Regenerate Pass") { Task { await model.regeneratePass() } }
                Button("Copy Installation Link") {
                    Task {
                        if let link = await model.createInstallLink() {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link.url, forType: .string)
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private var membership: some View {
        GroupCard(title: "Membership") {
            MetricRow(label: "PureGym", value: model.status?.puregym.accountEmail ?? "Not connected")
            MetricRow(label: "Home gym", value: model.status?.puregym.homeGym ?? "—")
            MetricRow(label: "Member", value: model.status?.puregym.memberName ?? "—")
            MetricRow(label: "Access code", value: (model.status?.qr.present ?? false) ? "Available" : "Not retrieved")
        }
    }

    private var services: some View {
        GroupCard(title: "Services") {
            ServiceRow(name: "Background service", state: model.agentReachable ? .healthy : .unavailable, detail: model.agentReachable ? "Running" : "Not running")
            ServiceRow(name: "PureGym", state: model.status?.puregym.state ?? .inactive)
            ServiceRow(name: "Wallet", state: model.status?.wallet.state ?? .inactive)
            ServiceRow(name: "Automatic updates", state: model.status?.tunnel.state ?? .inactive, detail: model.status?.tunnel.publicHostname)
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.m) {
            PrimaryActionButton(title: "Refresh Now", systemImage: "arrow.clockwise", isBusy: model.busy) {
                Task { await model.refreshQR() }
            }
            Button("Regenerate Pass") { Task { await model.regeneratePass() } }
            Button("Test Services") { Task { await model.testServices() } }
            Button("Add to Apple Wallet") {
                Task {
                    if let link = await model.createInstallLink() {
                        installLink = link
                        showingInstall = true
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }

    private var overallSymbol: String {
        switch model.status?.overall {
        case .healthy: "checkmark.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        case .unavailable: "xmark.circle.fill"
        default: "wallet.pass"
        }
    }

    private var overallColor: Color {
        switch model.status?.overall {
        case .healthy: .green
        case .attention: .orange
        case .unavailable: .red
        default: Theme.accent
        }
    }
}

struct InstallPassSheet: View {
    let link: InstallLink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Text("Add GymPass to Wallet")
                .font(.title2.weight(.semibold))
            Text("Scan this installation code with your iPhone. Keep it separate from your gym entry code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(spacing: Spacing.s) {
                QRCodeView(payload: link.url, size: 200)
                    .padding(Spacing.m)
                    .background(.white, in: RoundedRectangle(cornerRadius: Radius.container, style: .continuous))
                Text("Installation code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Installation QR code. Scan with your iPhone to add the pass.")

            HStack(spacing: Spacing.m) {
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link.url, forType: .string)
                }
                ShareLink(item: link.url) { Text("Share…") }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Text("This link expires \(link.expiresAt.formatted(date: .omitted, time: .shortened)). Anyone with the link can download the pass.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(Spacing.xxl)
        .frame(minWidth: 460)
    }
}
