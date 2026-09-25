import Foundation

public enum ActivityKind: String, Codable, Sendable {
    case qrRetrieved
    case qrUnchanged
    case passGenerated
    case passPublished
    case devicesNotified
    case notificationAccepted
    case notificationFailed
    case registrationReceived
    case registrationRemoved
    case deviceLookup
    case passServed
    case puregymChecked
    case endpointChecked
    case authRecovered
    case authRequiresAttention
    case certificateWarning
    case tunnelState
    case error

    public var symbolName: String {
        switch self {
        case .qrRetrieved, .qrUnchanged, .puregymChecked: "checkmark.circle.fill"
        case .passGenerated, .passPublished: "wallet.pass.fill"
        case .devicesNotified, .notificationAccepted: "bell.badge.fill"
        case .notificationFailed: "bell.slash.fill"
        case .registrationReceived, .registrationRemoved: "iphone.gen3"
        case .deviceLookup: "arrow.triangle.2.circlepath"
        case .passServed: "arrow.down.circle.fill"
        case .endpointChecked: "network"
        case .authRecovered: "person.badge.key.fill"
        case .authRequiresAttention: "person.badge.key"
        case .certificateWarning: "checkmark.seal"
        case .tunnelState: "point.3.connected.trianglepath.dotted"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    public var isProblem: Bool {
        switch self {
        case .notificationFailed, .authRequiresAttention, .certificateWarning, .error: true
        default: false
        }
    }
}

public struct ActivityEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var occurredAt: Date
    public var kind: ActivityKind
    public var title: String
    public var detail: String?
    public var metadata: [String: String]

    public init(id: Int64? = nil, occurredAt: Date = Date(), kind: ActivityKind, title: String, detail: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.title = title
        self.detail = detail
        self.metadata = metadata
    }
}
