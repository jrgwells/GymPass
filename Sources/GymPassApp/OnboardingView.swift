import SwiftUI
import GymPassShared

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var email = ""
    @State private var pin = ""
    @State private var connecting = false
    @State private var hostname = ""
    @State private var token = ""
    @State private var link: InstallLink?
    @State private var showingCertificateImport = false

    private let stepTitles = ["Welcome", "PureGym", "Apple Wallet", "Automatic Updates", "Ready"]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            progressIndicator
            Group {
                switch step {
                case 0: welcomeStep
                case 1: pureGymStep
                case 2: walletStep
                case 3: remoteStep
                default: readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(Spacing.xxl)
        .frame(width: 560, height: 520)
        .sheet(isPresented: $showingCertificateImport) { CertificateImportSheet() }
    }

    private var progressIndicator: some View {
        HStack(spacing: Spacing.s) {
            ForEach(stepTitles.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Theme.accent : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
        .accessibilityLabel("Step \(step + 1) of \(stepTitles.count): \(stepTitles[step])")
    }

    private var welcomeStep: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("GymPass")
                .font(.largeTitle.weight(.semibold))
            Text("Your gym pass, kept current.")
                .font(.title3)
            Text("GymPass keeps your PureGym access code up to date in Apple Wallet automatically, on iPhone and Apple Watch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    private var pureGymStep: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Connect your membership so GymPass can retrieve your current access code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Email", text: $email)
            SecureField("PIN", text: $pin)
            Text("Credentials are stored securely in your Mac's Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.status?.puregym.authenticationValid == true {
                StatusLabel(state: .healthy, text: "Connected — \(model.status?.puregym.homeGym ?? "PureGym")")
            }
            Button {
                connecting = true
                Task {
                    await model.send(.setPureGymCredentials(email: email, pin: pin))
                    connecting = false
                }
            } label: {
                if connecting { ProgressView().controlSize(.small) } else { Text("Connect") }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(email.isEmpty || pin.isEmpty || connecting)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var walletStep: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Apple Wallet needs a Pass Type ID certificate from your Apple Developer account before GymPass can create your pass.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let signing = model.status?.signing, signing.state == .healthy {
                StatusLabel(state: .healthy, text: "Certificate ready")
                if let passType = signing.passTypeIdentifier { MetricRow(label: "Pass Type ID", value: passType) }
            } else {
                StatusLabel(state: .warning, text: "Signing certificate required")
                Button("Choose Certificate…") { showingCertificateImport = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
    }

    private var remoteStep: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Apple Wallet needs a secure way to reach this Mac when your access code changes. This is optional; you can set it up later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Public hostname", text: $hostname, prompt: Text("wallet.example.com"))
                .textFieldStyle(.roundedBorder)
            SecureField("Tunnel token", text: $token)
                .textFieldStyle(.roundedBorder)
            Button("Save") {
                Task {
                    if !token.isEmpty { await model.send(.setTunnelToken(token)) }
                    var config = TunnelConfiguration(provider: .cloudflareNamed, publicHostname: hostname.isEmpty ? nil : hostname, hasStoredCredentials: !token.isEmpty)
                    config.localWalletPort = model.status?.server.port ?? 8754
                    await model.send(.configureTunnel(config))
                }
            }
            if model.status?.tunnel.state == .healthy {
                StatusLabel(state: .healthy, text: model.status?.tunnel.publicHostname ?? "Connected")
            } else if model.status?.tunnel.state == .notConfigured {
                StatusLabel(state: .notConfigured, text: "Not set up yet")
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("GymPass is ready")
                .font(.title2.weight(.semibold))
            if let link {
                QRCodeView(payload: link.url, size: 170)
                    .padding(Spacing.m)
                    .background(.white, in: RoundedRectangle(cornerRadius: Radius.container))
                Text("Scan with your iPhone to add the pass. Keep this separate from your gym entry code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            } else {
                Button("Create Installation Link") {
                    Task { link = await model.createInstallLink() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(model.status?.signing.state != .healthy)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            if step < 4 {
                Button(step == 0 ? "Get Started" : "Continue") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Done") {
                    model.showingOnboarding = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
