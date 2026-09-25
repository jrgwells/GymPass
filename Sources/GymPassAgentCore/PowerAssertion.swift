import Foundation
import IOKit.pwr_mgt
import GymPassCore

/// Optional visible sleep prevention. Only enabled by explicit user setting and
/// released when the service stops.
final class PowerAssertion: @unchecked Sendable {
    private var assertionID: IOPMAssertionID = 0
    private let lock = NSLock()

    func enable() {
        lock.lock()
        defer { lock.unlock() }
        guard assertionID == 0 else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "GymPass keeps your Wallet pass up to date" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
            Log.agent.info("Prevent-idle-sleep assertion enabled")
        }
    }

    func disable() {
        lock.lock()
        defer { lock.unlock() }
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        Log.agent.info("Prevent-idle-sleep assertion released")
    }
}
