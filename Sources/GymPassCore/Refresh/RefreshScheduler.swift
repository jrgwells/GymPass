import Foundation
import GymPassShared

public enum RefreshTrigger: String, Sendable {
    case scheduled
    case manual
    case startup
    case authRecovery
    case networkRecovery
    case wake
    case appRequest

    public var isImmediate: Bool {
        switch self {
        case .manual, .startup, .authRecovery, .networkRecovery, .wake, .appRequest: true
        case .scheduled: false
        }
    }
}

/// Pure scheduling decisions. Kept free of I/O so it can be exhaustively tested.
public enum RefreshScheduler {
    public static let minimumDelay: TimeInterval = 30
    public static let maximumDelay: TimeInterval = 6 * 3600

    /// Computes how long to wait before the next scheduled check.
    public static func nextDelay(
        policy: RefreshPolicy,
        qr: QRStatus?,
        failures: Int,
        hasPublishedPass: Bool,
        now: Date = Date(),
        jitter: Double = .random(in: -0.1...0.1)
    ) -> TimeInterval {
        if failures > 0 {
            let exponent = min(failures, 6)
            let backoff = min(Double(policy.floorIntervalSeconds) * pow(2, Double(exponent)), maximumDelay)
            return clamp(backoff * (1 + jitter))
        }

        let floor = max(minimumDelay, TimeInterval(policy.floorIntervalSeconds))
        let safety = TimeInterval(policy.expirySafetyMarginSeconds)

        guard let qr, hasPublishedPass else {
            return clamp(floor * (1 + jitter))
        }

        var candidate: TimeInterval?
        let expiryCandidate = qr.expiresAt.map { $0.timeIntervalSince(now) - safety }
        let refreshCandidate = qr.refreshAfter.map { $0.timeIntervalSince(now) }

        switch policy.mode {
        case .conservative:
            candidate = expiryCandidate ?? floor
        case .balanced:
            candidate = [refreshCandidate, expiryCandidate].compactMap { $0 }.min() ?? floor
        case .aggressive:
            candidate = floor
        }

        let value = max(candidate ?? floor, floor)
        return clamp(value * (1 + jitter))
    }

    private static func clamp(_ value: TimeInterval) -> TimeInterval {
        min(max(value, minimumDelay), maximumDelay)
    }
}
