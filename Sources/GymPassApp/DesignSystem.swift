import SwiftUI
import GymPassShared

/// GymPass design tokens. Colours are defined programmatically because the
/// project intentionally avoids asset catalogs (they require Xcode's actool).
enum Theme {
    static let accent = Color(red: 108.0 / 255, green: 77.0 / 255, blue: 255.0 / 255)
    static let accentStrong = Color(red: 87.0 / 255, green: 54.0 / 255, blue: 238.0 / 255)
    static let passPurple = Color(red: 106.0 / 255, green: 53.0 / 255, blue: 212.0 / 255)

    static func hex(_ string: String, fallback: Color = .secondary) -> Color {
        guard let rgb = HexColor.rgb(from: string) else { return fallback }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
}

enum Radius {
    static let control: CGFloat = 8
    static let container: CGFloat = 12
    static let focal: CGFloat = 18
}

/// Presentation for a service state. Colour is never the only indicator: every
/// state also carries a symbol and a text label.
struct StatePresentation {
    let symbol: String
    let color: Color
    let label: String

    init(_ state: ServiceState) {
        switch state {
        case .healthy:
            symbol = "checkmark.circle.fill"; color = .green; label = "Working"
        case .working:
            symbol = "arrow.triangle.2.circlepath"; color = Theme.accent; label = "Working"
        case .waiting:
            symbol = "clock"; color = .secondary; label = "Waiting"
        case .warning:
            symbol = "exclamationmark.circle.fill"; color = .orange; label = "Needs attention"
        case .unavailable:
            symbol = "xmark.circle.fill"; color = .red; label = "Unavailable"
        case .notConfigured:
            symbol = "circle.dashed"; color = .secondary; label = "Not configured"
        case .inactive:
            symbol = "minus.circle.fill"; color = .secondary; label = "Inactive"
        }
    }
}

struct StatusLabel: View {
    let state: ServiceState
    var text: String?

    var body: some View {
        let presentation = StatePresentation(state)
        Label {
            Text(text ?? presentation.label)
        } icon: {
            Image(systemName: presentation.symbol)
                .foregroundStyle(presentation.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text ?? presentation.label), \(presentation.label)")
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ServiceRow: View {
    let name: String
    let state: ServiceState
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Text(name)
                .font(.subheadline)
                .frame(width: 170, alignment: .leading)
            StatusLabel(state: state, text: detail)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct GroupCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.container, style: .continuous))
    }
}
