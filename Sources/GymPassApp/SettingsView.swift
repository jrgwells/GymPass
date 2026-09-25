import SwiftUI
import UniformTypeIdentifiers
import GymPassCore
import GymPassShared

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView(selection: Binding(get: { model.settingsTab }, set: { model.settingsTab = $0 })) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(AppModel.SettingsTab.general)
            PureGymSettings().tabItem { Label("PureGym", systemImage: "figure.run") }.tag(AppModel.SettingsTab.puregym)
            WalletSettings().tabItem { Label("Wallet", systemImage: "wallet.pass") }.tag(AppModel.SettingsTab.wallet)
            ConnectivitySettings().tabItem { Label("Connectivity", systemImage: "network") }.tag(AppModel.SettingsTab.connectivity)
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }.tag(AppModel.SettingsTab.advanced)
        }
        .frame(width: 540, height: 440)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var preferences = AppPreferences.default
    @State private var policy = RefreshPolicy.default
    @State private var syncedPreferences: AppPreferences?
    @State private var syncedPolicy: RefreshPolicy?

    private var agentEnabled: Bool {
        switch model.agentInstallation {
        case .enabled, .running: true
        default: false
        }
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Run GymPass in the background", isOn: Binding(
                    get: { agentEnabled },
                    set: { newValue in Task { newValue ? await model.installAgent() : await model.uninstallAgent() } }
                ))
                if model.agentInstallation == .requiresApproval {
                    Button("Open Login Items Settings…") { model.openApprovalSettings() }
                    Text("macOS needs approval before the background service can run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Keep this Mac awake while running", isOn: $preferences.keepMacAwake)
                    .onChange(of: preferences.keepMacAwake) { _, _ in sendPreferences() }
            }
            Section("Notifications") {
                Toggle("Important problems", isOn: $preferences.notifyImportantProblems)
                    .onChange(of: preferences.notifyImportantProblems) { _, _ in sendPreferences() }
                Toggle("Certificate expiry", isOn: $preferences.notifyCertificateExpiry)
                    .onChange(of: preferences.notifyCertificateExpiry) { _, _ in sendPreferences() }
            }
            Section("Access code updates") {
                Picker("Refresh strategy", selection: $policy.mode) {
                    ForEach(RefreshMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(policy.mode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply Refresh Strategy") {
                    Task { await model.send(.setRefreshPolicy(policy)) }
                }
                .disabled(syncedPolicy == policy)
            }
        }
        .formStyle(.grouped)
        .task { syncFromModel() }
        .onChange(of: model.status?.generatedAt) { _, _ in syncFromModel() }
    }

    private func sendPreferences() {
        syncedPreferences = preferences
        Task { await model.send(.setPreferences(preferences)) }
    }

    private func syncFromModel() {
        guard let status = model.status else { return }
        if syncedPreferences == nil || preferences == syncedPreferences {
            preferences = status.preferences
            syncedPreferences = status.preferences
        }
        if syncedPolicy == nil || policy == syncedPolicy {
            policy = status.refreshPolicy
            syncedPolicy = status.refreshPolicy
        }
    }
}

private struct PureGymSettings: View {
    @Environment(AppModel.self) private var model
    @State private var showingReconnect = false
    @State private var email = ""
    @State private var pin = ""
    @State private var error: String?
    @State private var connecting = false

    var body: some View {
        Form {
            Section("Account") {
                MetricRow(label: "Member", value: model.status?.puregym.memberName ?? "—")
                MetricRow(label: "Home gym", value: model.status?.puregym.homeGym ?? "—")
                StatusLabel(state: model.status?.puregym.state ?? .inactive, text: (model.status?.puregym.authenticationValid ?? false) ? "Connected" : "Not connected")
            }
            Section {
                Button("Reconnect…") { error = nil; showingReconnect = true }
                Button("Disconnect", role: .destructive) { Task { await model.send(.disconnectPureGym) } }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingReconnect) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Reconnect PureGym").font(.headline)
                TextField("Email", text: $email).frame(width: 280)
                SecureField("PIN", text: $pin).frame(width: 280)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if connecting { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Cancel") { showingReconnect = false }
                    Button("Connect") {
                        connecting = true
                        Task {
                            let response = await model.send(.setPureGymCredentials(email: email, pin: pin), silentOnFailure: true)
                            connecting = false
                            if case .failure(let payload) = response {
                                error = payload.message
                            } else {
                                showingReconnect = false
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(email.isEmpty || pin.isEmpty || connecting)
                }
            }
            .padding(Spacing.xxl)
            .frame(minWidth: 340)
        }
    }
}

private struct WalletSettings: View {
    @Environment(AppModel.self) private var model
    @State private var showingImport = false

    var body: some View {
        Form {
            Section("Signing") {
                MetricRow(label: "Pass Type ID", value: model.status?.signing.passTypeIdentifier ?? "Not configured")
                MetricRow(label: "Team ID", value: model.status?.signing.teamIdentifier ?? "—")
                MetricRow(label: "Expires", value: model.status?.signing.expiresAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                StatusLabel(state: model.status?.signing.state ?? .notConfigured)
            }
            Section {
                Button("Manage Certificate…") { showingImport = true }
                Button("Clear Certificate", role: .destructive) { Task { await model.send(.clearSigningIdentity) } }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingImport) {
            CertificateImportSheet()
        }
    }
}

struct CertificateImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var showingPicker = false
    @State private var selectedData: Data?
    @State private var fileName: String?
    @State private var error: String?
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Wallet Signing Certificate").font(.headline)
            Text("Select your Pass Type ID certificate (.p12) from the Apple Developer portal, then enter its password. The certificate and key are stored in your Mac's Keychain.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Choose Certificate…") { showingPicker = true }
                Text(fileName ?? "No file selected").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            SecureField("Certificate password", text: $password)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if importing { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Import") {
                    guard let data = selectedData else { return }
                    importing = true
                    Task {
                        let response = await model.send(.importSigningIdentity(p12: data, password: password), silentOnFailure: true)
                        importing = false
                        if case .failure(let payload) = response {
                            error = payload.message
                        } else {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedData == nil || importing)
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 460)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data]) { result in
            if case .success(let url) = result {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                selectedData = try? Data(contentsOf: url)
                fileName = url.lastPathComponent
                error = nil
            }
        }
    }
}

private struct ConnectivitySettings: View {
    @Environment(AppModel.self) private var model
    @State private var hostname = ""
    @State private var token = ""
    @State private var provider: TunnelProviderKind = .cloudflareNamed
    @State private var syncedHostname: String?
    @State private var syncedProvider: TunnelProviderKind?

    var body: some View {
        Form {
            Section("Automatic Updates") {
                Picker("Provider", selection: $provider) {
                    ForEach(TunnelProviderKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                TextField("Public hostname", text: $hostname, prompt: Text("wallet.example.com"))
                SecureField("Tunnel token", text: $token)
                HStack {
                    Button("Test Connection") { Task { await model.send(.testTunnel) } }
                    Button("Restart Tunnel") { Task { await model.send(.restartTunnel) } }
                    Button("Apply") {
                        Task {
                            if !token.isEmpty { await model.send(.setTunnelToken(token)) }
                            var config = TunnelConfiguration(provider: provider, publicHostname: hostname.isEmpty ? nil : hostname, hasStoredCredentials: !token.isEmpty)
                            config.localWalletPort = model.status?.server.port ?? 8754
                            await model.send(.configureTunnel(config))
                            token = ""
                            syncedHostname = hostname
                            syncedProvider = provider
                        }
                    }
                }
            }
            Section("Status") {
                StatusLabel(state: model.status?.tunnel.state ?? .notConfigured, text: model.status?.tunnel.publicHostname)
                if TunnelBinaryLocator.locate() == nil {
                    Text("cloudflared was not found. Install it with Homebrew: brew install cloudflared")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .task { syncFromModel() }
        .onChange(of: model.status?.generatedAt) { _, _ in syncFromModel() }
    }

    private func syncFromModel() {
        guard let status = model.status else { return }
        if syncedHostname == nil || hostname == syncedHostname {
            hostname = status.tunnel.publicHostname ?? ""
            syncedHostname = hostname
        }
        if syncedProvider == nil || provider == syncedProvider {
            provider = status.tunnel.provider
            syncedProvider = provider
        }
    }
}

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model
    @State private var showingResetRegistrations = false
    @State private var showingResetPass = false

    var body: some View {
        Form {
            Section("Background Service") {
                MetricRow(label: "Status", value: model.status?.agent.installation.phrase ?? "—")
                Button("Restart Background Service") { Task { await model.restartAgent() } }
                Button("Open Login Items Settings") { model.openApprovalSettings() }
            }
            Section("Local Wallet Server") {
                MetricRow(label: "Wallet API", value: "127.0.0.1:\(model.status?.server.port ?? 8754)")
                MetricRow(label: "Control API", value: "127.0.0.1:\(model.status?.server.controlPort ?? 8755)")
            }
            Section("Database") {
                MetricRow(label: "Location", value: model.status?.database.path ?? "—")
                MetricRow(label: "Schema", value: model.status?.database.migrationVersion ?? "—")
            }
            Section("Reset") {
                Button("Reset Wallet Registrations…", role: .destructive) { showingResetRegistrations = true }
                Button("Reset Pass…", role: .destructive) { showingResetPass = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset registrations?", isPresented: $showingResetRegistrations) {
            Button("Reset Registrations", role: .destructive) { Task { await model.send(.resetRegistrations) } }
        } message: {
            Text("Wallet devices will need to re-register. Your pass is not affected.")
        }
        .confirmationDialog("Reset the pass?", isPresented: $showingResetPass) {
            Button("Reset Pass", role: .destructive) { Task { await model.send(.resetPass) } }
        } message: {
            Text("GymPass will generate a new pass revision. Installed passes will update automatically.")
        }
    }
}
