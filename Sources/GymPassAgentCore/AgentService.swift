import Foundation
import GymPassCore
import GymPassShared

/// Entry point for the background service.
public enum AgentService {
    public static func run() async {
        let arguments = CommandLine.arguments
        if arguments.contains("--help") || arguments.contains("-h") {
            print("GymPass agent. Options: --agent, --demo")
            return
        }
        let demoMode = arguments.contains("--demo") || ProcessInfo.processInfo.environment["GYMPASS_DEMO"] == "1"

        do {
            let runtime = try await AgentRuntime.make(demoMode: demoMode)
            try await runtime.start()
            if demoMode {
                Log.agent.notice("GymPass agent running in DEMO mode")
            } else {
                Log.agent.notice("GymPass agent running")
            }
            await waitForever()
            await runtime.stop()
        } catch {
            Log.agent.error("Agent failed to start: \(Redactor.redact(String(describing: error)), privacy: .public)")
            exit(1)
        }
    }

    /// The agent is intended to run for the lifetime of the login session. We
    /// park rather than busy-loop; launchd stops the process with SIGTERM.
    private static func waitForever() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
        }
    }
}
