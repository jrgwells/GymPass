import SwiftUI
import GymPassShared

struct WalletView: View {
    @Environment(AppModel.self) private var model

    private struct LocationFields: Equatable {
        var use: Bool
        var label: String
        var latitude: String
        var longitude: String
    }

    @State private var draft: PassAppearance = .default
    @State private var lastSynced: PassAppearance?
    @State private var useLocation = false
    @State private var locationLabel = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var lastLocation: LocationFields?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                HStack {
                    Spacer()
                    PassPreviewView(
                        appearance: draft,
                        qrPayload: model.preview?.qrPayload,
                        memberName: model.preview?.memberName ?? model.status?.puregym.memberName,
                        updatedAt: model.status?.wallet.lastPublishedAt
                    )
                    Spacer()
                }

                GroupCard(title: "Status") {
                    MetricRow(label: "Current pass", value: passStateDescription)
                    MetricRow(label: "Serial", value: model.status?.wallet.serialNumber ?? "—")
                    MetricRow(label: "Last generated", value: model.status?.wallet.lastGeneratedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                    MetricRow(label: "Wallet registrations", value: "\(model.status?.wallet.registrationCount ?? 0)")
                }

                GroupCard(title: "Appearance") {
                    LabeledContent("Title") {
                        TextField("Title", text: $draft.title).frame(maxWidth: 220)
                    }
                    LabeledContent("Gym label") {
                        TextField("Gym", text: $draft.gymLabel).frame(maxWidth: 220)
                    }
                    Toggle("Show member name", isOn: $draft.showMemberName)
                    WrappingActionRow(spacing: Spacing.l) {
                        ColorPicker("Pass colour", selection: colorBinding(\.backgroundHex), supportsOpacity: false)
                        ColorPicker("Text colour", selection: colorBinding(\.foregroundHex), supportsOpacity: false)
                        ColorPicker("Label colour", selection: colorBinding(\.labelHex), supportsOpacity: false)
                    }
                    HStack(alignment: .top) {
                        Text("The exact rendering in Apple Wallet is controlled by iOS and watchOS; this is a close approximation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: Spacing.m)
                        Button("Apply & Regenerate") {
                            Task {
                                await model.send(.updateAppearance(draft), action: .regenerate)
                                await model.requestPreview()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(!hasUnsavedAppearanceEdits || model.isRegenerating)
                    }
                }

                GroupCard(title: "Location") {
                    Toggle("Surface near the gym", isOn: $useLocation)
                    if useLocation {
                        LabeledContent("Label") { TextField("Gym", text: $locationLabel).frame(maxWidth: 220) }
                        LabeledContent("Latitude") { TextField("51.3432", text: $latitude).frame(maxWidth: 220) }
                        LabeledContent("Longitude") { TextField("-0.6987", text: $longitude).frame(maxWidth: 220) }
                        if !locationFieldsValid {
                            Label("Enter a label and numeric latitude and longitude.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    HStack(alignment: .top) {
                        Text("Location relevance is optional and controlled by the system.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: Spacing.m)
                        Button("Apply Location") {
                            guard locationFieldsValid else { return }
                            Task {
                                await model.send(.updateLocation(useLocation ? parsedLocation : nil), action: .regenerate)
                                lastLocation = locationFields
                            }
                        }
                        .disabled(!locationFieldsValid || !hasUnsavedLocationEdits || model.isRegenerating)
                    }
                }

                HStack {
                    PrimaryActionButton(title: "Regenerate Pass", systemImage: "arrow.triangle.2.circlepath", isBusy: model.isRegenerating) {
                        Task { await model.regeneratePass() }
                    }
                }
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Wallet")
        .task { syncFromModel() }
        .onChange(of: model.preview?.revision) { _, _ in syncFromModel() }
        .onChange(of: model.status?.wallet.revision) { _, _ in syncFromModel() }
    }

    // MARK: - Sync

    private var locationFields: LocationFields {
        LocationFields(use: useLocation, label: locationLabel, latitude: latitude, longitude: longitude)
    }

    private var hasUnsavedAppearanceEdits: Bool {
        guard let lastSynced else { return false }
        return draft != lastSynced
    }

    private var hasUnsavedLocationEdits: Bool {
        guard let lastLocation else { return locationFields.use }
        return locationFields != lastLocation
    }

    /// Syncs the editor from the agent unless the user has unsaved changes, so
    /// their in-progress edits are never clobbered.
    private func syncFromModel() {
        if !hasUnsavedAppearanceEdits, let appearance = model.preview?.appearance ?? model.status?.wallet.appearance {
            draft = appearance
            lastSynced = appearance
        }
        if !hasUnsavedLocationEdits {
            let location = model.status?.wallet.location ?? model.status?.puregym.homeGymLocation
            if let location {
                useLocation = true
                locationLabel = location.label
                latitude = String(location.latitude)
                longitude = String(location.longitude)
            } else {
                useLocation = false
                locationLabel = ""
                latitude = ""
                longitude = ""
            }
            lastLocation = locationFields
        }
    }

    // MARK: - Helpers

    private var passStateDescription: String {
        guard let status = model.status else { return "—" }
        guard status.wallet.revision != nil else { return "Not generated" }
        if status.qr.reportedExpiryPassed { return "Access code may have expired" }
        if status.puregym.state == .warning { return "Updates delayed" }
        if status.tunnel.state == .notConfigured { return "Saved — automatic updates not configured" }
        return "Up to date"
    }

    private var locationFieldsValid: Bool {
        guard useLocation else { return true }
        return !locationLabel.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(latitude) != nil
            && Double(longitude) != nil
    }

    private var parsedLocation: PassLocation? {
        guard let lat = Double(latitude), let lon = Double(longitude) else { return nil }
        return PassLocation(label: locationLabel, latitude: lat, longitude: lon)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<PassAppearance, String>) -> Binding<Color> {
        Binding(
            get: { Theme.hex(draft[keyPath: keyPath], fallback: .white) },
            set: { newValue in
                let nsColor = NSColor(newValue).usingColorSpace(.sRGB) ?? .white
                let hex = String(format: "#%02X%02X%02X",
                                 Int((nsColor.redComponent * 255).rounded()),
                                 Int((nsColor.greenComponent * 255).rounded()),
                                 Int((nsColor.blueComponent * 255).rounded()))
                draft[keyPath: keyPath] = hex
            }
        )
    }
}
