import Foundation

public enum AgentRequest: Codable, Sendable, Equatable {
    case getStatus
    case refreshQR
    case regeneratePass
    case runDiagnostic(DiagnosticKind)
    case setPureGymCredentials(email: String, pin: String)
    case connectPureGym
    case disconnectPureGym
    case importSigningIdentity(p12: Data, password: String)
    case clearSigningIdentity
    case configureTunnel(TunnelConfiguration)
    case setTunnelToken(String)
    case restartTunnel
    case testTunnel
    case testAPNs
    case updateAppearance(PassAppearance)
    case updateLocation(PassLocation?)
    case setRefreshPolicy(RefreshPolicy)
    case setPreferences(AppPreferences)
    case createInstallLink
    case resetRegistrations
    case resetPass
    case exportDiagnostics
    case listActivity(limit: Int)
    case passPreview
    case ping
}

/// A local-only preview payload. It contains the current access code so the GUI
/// can render an accurate preview. It is only ever sent over the loopback
/// control channel and is never logged or persisted.
public struct PassPreview: Codable, Sendable, Equatable {
    public var qrPayload: String
    public var serialNumber: String
    public var passTypeIdentifier: String
    public var memberName: String?
    public var gymLabel: String
    public var appearance: PassAppearance
    public var revision: Int
    public var updatedAt: Date

    public init(qrPayload: String, serialNumber: String, passTypeIdentifier: String, memberName: String?, gymLabel: String, appearance: PassAppearance, revision: Int, updatedAt: Date) {
        self.qrPayload = qrPayload
        self.serialNumber = serialNumber
        self.passTypeIdentifier = passTypeIdentifier
        self.memberName = memberName
        self.gymLabel = gymLabel
        self.appearance = appearance
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

public enum AgentResponse: Codable, Sendable, Equatable {
    case ok
    case status(StatusSnapshot)
    case activity([ActivityEvent])
    case diagnostic(DiagnosticReport)
    case installLink(InstallLink)
    case passPreview(PassPreview)
    case text(String)
    case failure(AgentErrorPayload)

    public var failurePayload: AgentErrorPayload? {
        if case .failure(let payload) = self { return payload }
        return nil
    }
}

public struct AgentErrorPayload: Codable, Sendable, Equatable, Error {
    public var code: String
    public var message: String
    public var detail: String?

    public init(code: String, message: String, detail: String? = nil) {
        self.code = code
        self.message = message
        self.detail = detail
    }
}

public struct InstallLink: Codable, Sendable, Equatable {
    public var url: String
    public var token: String
    public var expiresAt: Date
    public var passTypeIdentifier: String
    public var serialNumber: String

    public init(url: String, token: String, expiresAt: Date, passTypeIdentifier: String, serialNumber: String) {
        self.url = url
        self.token = token
        self.expiresAt = expiresAt
        self.passTypeIdentifier = passTypeIdentifier
        self.serialNumber = serialNumber
    }
}

public enum AgentProtocol {
    public static let version = 2
    public static let controlTokenHeader = "X-GymPass-Control-Token"
    public static let statusPath = "/control/status"
    public static let requestPath = "/control/request"
    public static let activityPath = "/control/activity"
    public static let healthPath = "/health"
}

public struct ControlEndpointFile: Codable, Sendable, Equatable {
    public var pid: Int
    public var controlPort: Int
    public var walletPort: Int
    public var token: String
    public var protocolVersion: Int
    public var startedAt: Date

    public init(pid: Int, controlPort: Int, walletPort: Int, token: String, protocolVersion: Int, startedAt: Date) {
        self.pid = pid
        self.controlPort = controlPort
        self.walletPort = walletPort
        self.token = token
        self.protocolVersion = protocolVersion
        self.startedAt = startedAt
    }
}
