import SwiftUI
import UniformTypeIdentifiers
import GymPassShared

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            PureGymSettings().tabItem { Label("PureGym", systemImage: "figure.run") }
            WalletSettings().tabItem { Label("Wallet", systemImage: "wallet.pass") }
            ConnectivitySettings().tabItem { Label("Connectivity", systemImage: "network") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 540, height: 420)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var preferences = AppPreferences.default
    @State private var policy = RefreshPolicy.default
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Run GymPass in the background", isOn: Binding(
                    get: { model.agentReachable },
                    set: { newValue in Task { newValue ? await model.installAgent() : await model.uninstallAgent() } }
                ))
                Toggle("Keep this Mac awake while running", isOn: $preferences.keepMacAwake)
                    .onChange(of: preferences.keepMacAwake) { _, _ in Task { await model.send(.setPreferences(preferences)) } }
            }
            Section("Notifications") {
                Toggle("Important problems", isOn: $preferences.notifyImportantProblems)
                    .onChange(of: preferences.notifyImportantProblems) { _, _ in Task { await model.send(.setPreferences(preferences)) } }
                Toggle("Certificate expiry", isOn: $preferences.notifyCertificateExpiry)
                    .onChange(of: preferences.notifyCertificateExpiry) { _, _ in Task { await model.send(.setPreferences(preferences)) } }
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
                Button("Apply") { Task { await model.send(.setRefreshPolicy(policy)) } }
            }
        }
        .formStyle(.grouped)
        .task {
            guard !loaded else { return }
            loaded = true
            if let status = model.status {
                preferences = AppPreferences(keepMacAwake: status.agent.inDemoMode ? false : preferences.keepMacAwake)
            }
        }
    }
}

private struct PureGymSettings: View {
    @Environment(AppModel.self) private var model
    @State private var showingReconnect = false
    @State private var email = ""
    @State private var pin = ""

    var body: some View {
        Form {
            Section("Account") {
                MetricRow(label: "Member", value: model.status?.puregym.memberName ?? "—")
                MetricRow(label: "Home gym", value: model.status?.puregym.homeGym ?? "—")
                StatusLabel(state: model.status?.puregym.state ?? .inactive, text: (model.status?.puregym.authenticationValid ?? false) ? "Connected" : "Not connected")
            }
            Section {
                Button("Reconnect…") { showingReconnect = true }
                Button("Disconnect", role: .destructive) { Task { await model.send(.disconnectPureGym) } }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingReconnect) {
            VStack(spacing: Spacing.l) {
                Text("Reconnect PureGym").font(.headline)
                TextField("Email", text: $email).frame(width: 280)
                SecureField("PIN", text: $pin).frame(width: 280)
                HStack {
                    Button("Cancel") { showingReconnect = false }
                    Button("Connect") {
                        Task {
                            await model.send(.setPureGymCredentials(email: email, pin: pin))
                            showingReconnect = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Spacing.xxl)
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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Wallet Signing Certificate").font(.headline)
            Text("Select your Pass Type ID certificate (.p12) from the Apple Developer portal, then enter its password. The certificate and key are stored in your Mac's Keychain.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Choose Certificate…") { showingPicker = true }
                Text(fileName ?? "No file selected").font(.caption).foregroundStyle(.secondary)
            }
            SecureField("Certificate password", text: $password)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Import") {
                    guard let data = selectedData else { return }
                    Task {
                        await model.send(.importSigningIdentity(p12: data, password: password))
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedData == nil)
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
            }
        }
    }
}

private struct ConnectivitySettings: View {
    @Environment(AppModel.self) private var model
    @State private var hostname = ""
    @State private var token = ""
    @State private var provider: TunnelProviderKind = .cloudflareNamed

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
                        }
                    }
                }
            }
            Section("Status") {
                StatusLabel(state: model.status?.tunnel.state ?? .notConfigured, text: model.status?.tunnel.publicHostname)
            }
        }
        .formStyle(.grouped)
        .task {
            hostname = model.status?.tunnel.publicHostname ?? ""
            provider = model.status?.tunnel.provider ?? .cloudflareNamed
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
