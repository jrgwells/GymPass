import Foundation
import GymPassShared

/// Short-lived, single-purpose capability tokens for installing the pass.
/// They are independent from the Wallet authentication token and grant only
/// the ability to download the current archive.
public actor InstallationLinkStore {
    public struct Link: Codable, Sendable, Equatable {
        public var token: String
        public var passTypeIdentifier: String
        public var serialNumber: String
        public var hostname: String
        public var expiresAt: Date
    }

    private var links: [String: Link] = [:]

    public init() {}

    public func create(passTypeIdentifier: String, serialNumber: String, hostname: String, ttl: TimeInterval = 900) -> InstallLink {
        prune()
        let token = SecureRandom.token(byteCount: 32)
        let link = Link(
            token: token,
            passTypeIdentifier: passTypeIdentifier,
            serialNumber: serialNumber,
            hostname: hostname,
            expiresAt: Date().addingTimeInterval(ttl)
        )
        links[token] = link
        let url = "https://\(hostname)/install/\(token)"
        return InstallLink(url: url, token: token, expiresAt: link.expiresAt, passTypeIdentifier: passTypeIdentifier, serialNumber: serialNumber)
    }

    public func resolve(token: String) -> Link? {
        prune()
        guard let link = links[token], link.expiresAt > Date() else { return nil }
        return link
    }

    public func revokeAll() {
        links.removeAll()
    }

    private func prune() {
        let now = Date()
        links = links.filter { $0.value.expiresAt > now }
    }
}
