import SwiftUI
import GymPassShared

struct WalletView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: PassAppearance = .default
    @State private var useLocation = false
    @State private var locationLabel = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var loaded = false

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
                        TextField("Title", text: $draft.title).frame(width: 220)
                    }
                    LabeledContent("Gym label") {
                        TextField("Gym", text: $draft.gymLabel).frame(width: 220)
                    }
                    Toggle("Show member name", isOn: $draft.showMemberName)
                    HStack(spacing: Spacing.xl) {
                        ColorPicker("Pass colour", selection: colorBinding(\.backgroundHex), supportsOpacity: false)
                        ColorPicker("Text colour", selection: colorBinding(\.foregroundHex), supportsOpacity: false)
                        ColorPicker("Label colour", selection: colorBinding(\.labelHex), supportsOpacity: false)
                    }
                    HStack {
                        Text("The exact rendering in Apple Wallet is controlled by iOS and watchOS; this is a close approximation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Apply & Regenerate") {
                            Task {
                                await model.send(.updateAppearance(draft))
                                await model.send(.passPreview)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                }

                GroupCard(title: "Location") {
                    Toggle("Surface near the gym", isOn: $useLocation)
                    if useLocation {
                        LabeledContent("Label") { TextField("Gym", text: $locationLabel).frame(width: 220) }
                        LabeledContent("Latitude") { TextField("51.3432", text: $latitude).frame(width: 220) }
                        LabeledContent("Longitude") { TextField("-0.6987", text: $longitude).frame(width: 220) }
                    }
                    HStack {
                        Text("Location relevance is optional and controlled by the system.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Apply Location") {
                            Task {
                                let location: PassLocation? = useLocation
                                    ? PassLocation(label: locationLabel, latitude: Double(latitude) ?? 0, longitude: Double(longitude) ?? 0)
                                    : nil
                                await model.send(.updateLocation(location))
                            }
                        }
                    }
                }

                HStack {
                    PrimaryActionButton(title: "Regenerate Pass", systemImage: "arrow.triangle.2.circlepath", isBusy: model.busy) {
                        Task { await model.regeneratePass() }
                    }
                }
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Wallet")
        .task {
            guard !loaded else { return }
            loaded = true
            await model.send(.passPreview)
            if let appearance = model.preview?.appearance ?? model.status?.wallet.appearance {
                draft = appearance
            }
            if let location = model.status?.wallet.location ?? model.status?.puregym.homeGymLocation {
                useLocation = true
                locationLabel = location.label
                latitude = String(location.latitude)
                longitude = String(location.longitude)
            }
        }
    }

    private var passStateDescription: String {
        guard let status = model.status else { return "—" }
        if status.wallet.revision == nil { return "Not generated" }
        return "Up to date"
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
