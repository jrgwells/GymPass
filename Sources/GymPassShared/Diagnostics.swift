import Foundation

public enum DiagnosticKind: String, Codable, Sendable, CaseIterable {
    case full
    case puregym
    case signing
    case apns
    case localServer
    case publicEndpoint
    case database
    case agent

    public var displayName: String {
        switch self {
        case .full: "Full Diagnostic"
        case .puregym: "Test PureGym"
        case .signing: "Test Signing"
        case .apns: "Test Apple Push"
        case .localServer: "Test Local Server"
        case .publicEndpoint: "Test Remote Access"
        case .database: "Check Database"
        case .agent: "Check Background Service"
        }
    }
}

public struct DiagnosticCheck: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var state: ServiceState
    public var summary: String
    public var detail: String?
    public var durationMilliseconds: Int?

    public init(name: String, state: ServiceState, summary: String, detail: String? = nil, durationMilliseconds: Int? = nil) {
        self.name = name
        self.state = state
        self.summary = summary
        self.detail = detail
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct DiagnosticReport: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var overall: ServiceState
    public var checks: [DiagnosticCheck]
    public var redacted: Bool

    public init(generatedAt: Date = Date(), overall: ServiceState, checks: [DiagnosticCheck], redacted: Bool = true) {
        self.generatedAt = generatedAt
        self.overall = overall
        self.checks = checks
        self.redacted = redacted
    }
}

public enum DiagnosticRedaction {
    /// Central list of patterns that must never appear in exported diagnostics.
    public static let sensitiveKeys: Set<String> = [
        "password", "pin", "token", "accessToken", "refreshToken", "authorization",
        "qr", "qrCode", "authenticationToken", "p12", "privateKey", "pushToken",
        "installToken", "deviceLibraryIdentifier", "secret", "credential",
    ]
}
