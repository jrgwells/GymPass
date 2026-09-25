import SwiftUI
import GymPassShared

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var didSetStartStep = false
    @State private var email = ""
    @State private var pin = ""
    @State private var connecting = false
    @State private var connectError: String?
    @State private var hostname = ""
    @State private var token = ""
    @State private var link: InstallLink?
    @State private var showingCertificateImport = false

    private let stepTitles = ["Welcome", "PureGym", "Apple Wallet", "Automatic Updates", "Ready"]

    var body: some View {
        VStack(spacing: Spacing.l) {
            header
            progressIndicator
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(Spacing.xxl)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 540)
        .onAppear {
            guard !didSetStartStep else { return }
            didSetStartStep = true
            step = min(max(model.onboardingStartStep, 0), stepTitles.count - 1)
        }
        .sheet(isPresented: $showingCertificateImport) { CertificateImportSheet() }
    }

    private var header: some View {
        HStack {
            Text(stepTitles[step])
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.showingOnboarding = false
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close setup")
            .help("Close setup")
        }
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

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: pureGymStep
        case 2: walletStep
        case 3: remoteStep
        default: readyStep
        }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pureGymStep: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Connect your membership so GymPass can retrieve your current access code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Email", text: $email)
            SecureField("PIN", text: $pin)
            Text("Credentials are stored securely in your Mac's Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let connectError {
                Label(connectError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.status?.puregym.authenticationValid == true {
                StatusLabel(state: .healthy, text: "Connected — \(model.status?.puregym.homeGym ?? "PureGym")")
            }
            HStack {
                if connecting { ProgressView().controlSize(.small) }
                Button("Connect") {
                    connecting = true
                    connectError = nil
                    Task {
                        let response = await model.send(.setPureGymCredentials(email: email, pin: pin), silentOnFailure: true)
                        connecting = false
                        if case .failure(let payload) = response {
                            connectError = payload.message
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(email.isEmpty || pin.isEmpty || connecting)
            }
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                if model.status?.signing.state != .healthy {
                    Text("A signing certificate is required before a pass can be installed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Button("Skip Setup") {
                model.showingOnboarding = false
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            if step < stepTitles.count - 1 {
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
