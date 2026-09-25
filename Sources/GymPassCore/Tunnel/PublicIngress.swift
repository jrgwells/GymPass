import Foundation
import GymPassShared

public protocol PublicIngressProvider: Sendable {
    var kind: TunnelProviderKind { get }
    func start() async throws
    func stop() async
    func status() async -> TunnelStatus
    func healthCheck() async -> PublicEndpointStatus
}

public enum TunnelBinaryLocator {
    /// Searches for a `cloudflared` executable. Never downloads anything.
    public static func locate() -> URL? {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["GYMPASS_CLOUDFLARED"] {
            candidates.append(override)
        }
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("cloudflared").path {
            candidates.append(resource)
        }
        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent().path {
            candidates.append((executableDir as NSString).appendingPathComponent("cloudflared"))
        }
        candidates.append(NSHomeDirectory() + "/Library/Application Support/GymPass/bin/cloudflared")
        candidates.append("/opt/homebrew/bin/cloudflared")
        candidates.append("/usr/local/bin/cloudflared")
        candidates.append("/usr/bin/cloudflared")

        let fileManager = FileManager.default
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

final class ProcessOutputCollector: @unchecked Sendable {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
}
