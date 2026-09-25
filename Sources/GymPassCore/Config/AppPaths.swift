import Foundation

public enum AppPaths {
    public static let bundleIdentifier = "com.jackwells.gympass"

    public static func applicationSupport() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("GymPass", isDirectory: true)
    }

    public static func logsDirectory() -> URL {
        applicationSupport().appendingPathComponent("Logs", isDirectory: true)
    }

    public static func databaseURL() -> URL {
        applicationSupport().appendingPathComponent("gympass.sqlite")
    }

    public static func controlEndpointURL() -> URL {
        applicationSupport().appendingPathComponent("control.json")
    }

    public static func installWorkingDirectory() -> URL {
        applicationSupport().appendingPathComponent("Install", isDirectory: true)
    }

    @discardableResult
    public static func ensureDirectories() throws -> URL {
        let support = applicationSupport()
        let fm = FileManager.default
        for url in [support, logsDirectory(), installWorkingDirectory()] {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
        }
        return support
    }

    public static func restrictPermissions(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
