import Foundation
import GymPassShared

/// A simple, bounded rate limiter shared by scheduled and manual callers.
/// It never busy-waits: callers `await acquire()` and sleep only as needed.
public actor RateLimiter {
    private let minimumInterval: TimeInterval
    private var lastRequestAt: Date?
    private var retryNotBefore: Date?

    public init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    /// Records a `Retry-After` instruction from the server.
    public func noteRetryAfter(seconds: Int) {
        retryNotBefore = Date().addingTimeInterval(TimeInterval(max(0, seconds)))
    }

    /// Suspends until a request is permitted, then records the request time.
    public func acquire() async {
        let now = Date()
        var wait: TimeInterval = 0
        if let retryNotBefore, retryNotBefore > now {
            wait = retryNotBefore.timeIntervalSince(now)
        }
        if let lastRequestAt {
            let elapsed = now.timeIntervalSince(lastRequestAt)
            if elapsed < minimumInterval {
                wait = max(wait, minimumInterval - elapsed)
            }
        }
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        lastRequestAt = Date()
    }
}
