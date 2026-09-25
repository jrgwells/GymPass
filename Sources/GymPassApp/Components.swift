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

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.m : Spacing.l) {
            HStack {
                Text(appearance.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(foreground.opacity(0.85))
                    .lineLimit(1)
                Spacer()
                Text("PureGym")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(foreground.opacity(0.75))
            }

            Text(appearance.gymLabel)
                .font(compact ? .headline : .title3.weight(.semibold))
                .foregroundStyle(foreground)
                .lineLimit(2)

            HStack {
                Spacer()
                qrBlock
                Spacer()
            }

            if appearance.showMemberName, let memberName, !memberName.isEmpty {
                Text(memberName)
                    .font(.headline)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
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

    @ViewBuilder
    private var qrBlock: some View {
        let side: CGFloat = compact ? 110 : 150
        if let qrPayload, let image = QRCodeRenderer.image(for: qrPayload) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .padding(Spacing.m)
                .background(.white, in: RoundedRectangle(cornerRadius: Radius.container, style: .continuous))
                .accessibilityHidden(true)
        } else {
            VStack(spacing: Spacing.s) {
                Image(systemName: qrPayload == nil ? "qrcode" : "exclamationmark.triangle")
                    .font(.system(size: 40))
                Text(qrPayload == nil
                     ? "Your access code appears here once the pass is generated."
                     : "The access code could not be rendered.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(foreground.opacity(0.8))
            .frame(width: side, height: side)
            .padding(Spacing.m)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.container, style: .continuous))
        }
    }

    private var accessibilitySummary: String {
        var parts = ["GymPass Wallet pass.", appearance.gymLabel]
        if let memberName, !memberName.isEmpty { parts.append(memberName) }
        parts.append(qrPayload == nil ? "Access code not ready." : "Access code ready.")
        if let updatedAt { parts.append("Updated \(DurationFormatter.minutesAgo(updatedAt)).") }
        return parts.joined(separator: " ")
    }
}

/// Centres an empty state in the available content area.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Two children side by side when there is room, stacked vertically when there
/// is not. Avoids horizontal overflow at the minimum window width.
struct AdaptivePair<First: View, Second: View>: View {
    var minimumChildWidth: CGFloat = 300
    @ViewBuilder var first: First
    @ViewBuilder var second: Second

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.section) {
                first.frame(minWidth: minimumChildWidth, maxWidth: .infinity, alignment: .topLeading)
                second.frame(minWidth: minimumChildWidth, maxWidth: .infinity, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: Spacing.m) {
                first
                second
            }
        }
    }
}

/// A simple wrapping layout so action clusters never overflow horizontally.
struct FlowLayout: Layout {
    var spacing: CGFloat = Spacing.s
    var rowSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + (rowSpacing ?? spacing)
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + (rowSpacing ?? spacing)
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct WrappingActionRow<Content: View>: View {
    var spacing: CGFloat = Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayout(spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineBanner: View {
    let message: AppModel.BannerMessage
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(message.isError ? .orange : Theme.accent)
            Text(message.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.s)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
                .help("Dismiss")
            }
        }
        .padding(Spacing.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.container, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
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
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 0, idealWidth: 150, maxWidth: 170, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
