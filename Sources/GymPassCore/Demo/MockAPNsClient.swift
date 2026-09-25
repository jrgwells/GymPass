import Foundation
import GymPassShared

/// APNs stand-in used by demo mode and tests.
public actor MockAPNsClient: APNsSending {
    public enum Behavior: String, Sendable {
        case accept
        case invalidToken
        case transient
        case reject
    }

    private var behavior: Behavior = .accept
    public private(set) var sentCount = 0

    public init(behavior: Behavior = .accept) {
        self.behavior = behavior
    }

    public func setBehavior(_ behavior: Behavior) {
        self.behavior = behavior
    }

    public func send(pushToken: Data, policy: WalletAPNsPolicy) async -> APNsResult {
        sentCount += 1
        switch behavior {
        case .accept: return .accepted(apnsID: UUID().uuidString)
        case .invalidToken: return .invalidToken(reason: "BadDeviceToken")
        case .transient: return .transient(status: 503, reason: "ServiceUnavailable")
        case .reject: return .rejected(status: 400, reason: "BadRequest")
        }
    }
}
