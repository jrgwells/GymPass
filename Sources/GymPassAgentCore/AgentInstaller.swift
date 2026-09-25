import Foundation
import GymPassCore
import GymPassShared

/// Installs and supervises the background agent.
///
/// The agent is a per-user LaunchAgent. When the app is signed with a Team ID
/// and the embedded helper is present, `SMAppService` is preferred; otherwise
/// GymPass falls back to writing a LaunchAgent plist and bootstrapping it with
/// `launchctl`, which works with ad-hoc signing.
public actor AgentInstaller {
    public static let label = "com.jackwells.gympass.agent"

    private let executablePath: String
    private let useSMAppService: Bool

    public init(executablePath: String = Bundle.main.executablePath ?? "", useSMAppService: Bool = false) {
        self.executablePath = executablePath
        self.useSMAppService = useSMAppService
    }

    public var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
    }

    public func status() async -> AgentInstallationStatus {
        guard !executablePath.isEmpty else { return .unavailable }
        let result = await Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(Self.label)"])
        if result.status == 0 {
            return result.output.contains("state = running") ? .running : .enabled
        }
        if FileManager.default.fileExists(atPath: plistURL.path) {
            return .requiresApproval
        }
        return .notInstalled
    }

    public func install() async throws {
        guard !executablePath.isEmpty else {
            throw GymPassError.internalError("The agent executable path could not be determined.")
        }
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist = Self.plistContents(executablePath: executablePath)
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)

        _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(Self.label)"])
        let bootstrap = await Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        guard bootstrap.status == 0 else {
            throw GymPassError.internalError("launchctl bootstrap failed: \(Redactor.redact(bootstrap.output))")
        }
        _ = await Shell.run("/bin/launchctl", ["enable", "gui/\(getuid())/\(Self.label)"])
        Log.agent.info("Background agent installed and bootstrapped")
    }

    public func uninstall() async throws {
        _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(Self.label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
        Log.agent.info("Background agent uninstalled")
    }

    public func openApprovalSettings() {
        Shell.runDetached("/usr/bin/open", ["x-apple.systempreferences:com.apple.LoginItems-Settings.extension"])
    }

    static func plistContents(executablePath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
                <string>--agent</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>ThrottleInterval</key>
            <integer>10</integer>
            <key>ProcessType</key>
            <string>Background</string>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
        </dict>
        </plist>
        """
    }
}

enum Shell {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(status: -1, output: String(describing: error)))
                return
            }
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: Result(status: process.terminationStatus, output: output))
        }
    }

    static func runDetached(_ launchPath: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try? process.run()
    }
}
