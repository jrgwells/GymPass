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
    case ping
}

public enum AgentResponse: Codable, Sendable, Equatable {
    case ok
    case status(StatusSnapshot)
    case activity([ActivityEvent])
    case diagnostic(DiagnosticReport)
    case installLink(InstallLink)
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
    public static let version = 1
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
