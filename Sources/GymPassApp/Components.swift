import SwiftUI
import GymPassShared

struct PassPreviewView: View {
    let appearance: PassAppearance
    let qrPayload: String?
    let memberName: String?
    let updatedAt: Date?
    var compact = false

    private var foreground: Color { Theme.hex(appearance.foregroundHex, fallback: .white) }
    private var background: Color { Theme.hex(appearance.backgroundHex, fallback: Theme.passPurple) }
    private var label: Color { Theme.hex(appearance.labelHex, fallback: .white.opacity(0.8)) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.m : Spacing.l) {
            HStack {
                Text(appearance.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(foreground.opacity(0.85))
                Spacer()
                Text("PureGym")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(foreground.opacity(0.75))
            }

            Text(appearance.gymLabel)
                .font(compact ? .headline : .title3.weight(.semibold))
                .foregroundStyle(foreground)

            HStack {
                Spacer()
                if let qrPayload {
                    Image(nsImage: QRCodeRenderer.image(for: qrPayload) ?? NSImage())
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: compact ? 110 : 150, height: compact ? 110 : 150)
                        .padding(Spacing.m)
                        .background(.white, in: RoundedRectangle(cornerRadius: Radius.container, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    VStack(spacing: Spacing.s) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 48))
                        Text("Your access code appears here once the pass is generated.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(foreground.opacity(0.8))
                    .frame(width: compact ? 110 : 150, height: compact ? 110 : 150)
                    .padding(Spacing.m)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.container, style: .continuous))
                }
                Spacer()
            }

            if appearance.showMemberName, let memberName, !memberName.isEmpty {
                Text(memberName)
                    .font(.headline)
                    .foregroundStyle(foreground)
            }

            if let updatedAt {
                Text("Updated \(DurationFormatter.minutesAgo(updatedAt))")
                    .font(.caption)
                    .foregroundStyle(foreground.opacity(0.75))
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: compact ? 320 : 420)
        .background(
            RoundedRectangle(cornerRadius: Radius.focal, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.focal, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = ["GymPass Wallet pass.", appearance.gymLabel]
        if let memberName, !memberName.isEmpty { parts.append(memberName) }
        parts.append(qrPayload == nil ? "Access code not ready." : "Access code ready.")
        if let updatedAt { parts.append("Updated \(DurationFormatter.minutesAgo(updatedAt)).") }
        return parts.joined(separator: " ")
    }
}

struct InlineBanner: View {
    let message: AppModel.BannerMessage

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(message.isError ? .orange : Theme.accent)
            Text(message.text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.container, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct PrimaryActionButton: View {
    let title: String
    var systemImage: String?
    var isBusy: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(minWidth: 120)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(isBusy)
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)
            Text(value)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension Color {
    static var tertiaryFill: Color { Color(nsColor: .tertiarySystemFill) }
}
