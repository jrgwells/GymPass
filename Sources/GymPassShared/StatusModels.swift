import Foundation

/// Summary state used throughout the UI. Never colour-only in the interface.
public enum ServiceState: String, Codable, Sendable, CaseIterable {
    case healthy
    case working
    case waiting
    case warning
    case unavailable
    case notConfigured
    case inactive

    /// Short human phrase for the state, suitable for accessibility.
    public var phrase: String {
        switch self {
        case .healthy: "Healthy"
        case .working: "Working"
        case .waiting: "Waiting"
        case .warning: "Needs attention"
        case .unavailable: "Unavailable"
        case .notConfigured: "Not configured"
        case .inactive: "Inactive"
        }
    }

    public var isProblem: Bool {
        switch self {
        case .warning, .unavailable: true
        default: false
        }
    }
}

public enum HealthLevel: String, Codable, Sendable {
    case healthy
    case attention
    case unavailable
    case setup
}

public struct StatusSnapshot: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var overall: HealthLevel
    public var overallTitle: String
    public var overallDetail: String
    public var agent: AgentStatus
    public var puregym: PureGymStatus
    public var wallet: WalletStatus
    public var signing: SigningStatus
    public var apns: APNsStatus
    public var server: ServerStatus
    public var tunnel: TunnelStatus
    public var publicEndpoint: PublicEndpointStatus
    public var database: DatabaseStatus
    public var qr: QRStatus
    public var preferences: AppPreferences
    public var refreshPolicy: RefreshPolicy

    public init(
        generatedAt: Date = Date(),
        overall: HealthLevel,
        overallTitle: String,
        overallDetail: String,
        agent: AgentStatus,
        puregym: PureGymStatus,
        wallet: WalletStatus,
        signing: SigningStatus,
        apns: APNsStatus,
        server: ServerStatus,
        tunnel: TunnelStatus,
        publicEndpoint: PublicEndpointStatus,
        database: DatabaseStatus,
        qr: QRStatus,
        preferences: AppPreferences = .default,
        refreshPolicy: RefreshPolicy = .default
    ) {
        self.generatedAt = generatedAt
        self.overall = overall
        self.overallTitle = overallTitle
        self.overallDetail = overallDetail
        self.agent = agent
        self.puregym = puregym
        self.wallet = wallet
        self.signing = signing
        self.apns = apns
        self.server = server
        self.tunnel = tunnel
        self.publicEndpoint = publicEndpoint
        self.database = database
        self.qr = qr
        self.preferences = preferences
        self.refreshPolicy = refreshPolicy
    }
}

public struct AgentStatus: Codable, Sendable, Equatable {
    public var state: ServiceState
    public var pid: Int?
    public var startedAt: Date?
    public var version: String
    public var installation: AgentInstallationStatus
    public var protocolVersion: Int
    public var inDemoMode: Bool
    public init(state: ServiceState, pid: Int?, startedAt: Date?, version: String, installation: AgentInstallationStatus, protocolVersion: Int, inDemoMode: Bool) {
        self.state = state; self.pid = pid; self.startedAt = startedAt
        self.version = version; self.installation = installation
        self.protocolVersion = protocolVersion; self.inDemoMode = inDemoMode
    }
}

public enum AgentInstallationStatus: String, Codable, Sendable {
    case notInstalled
    case requiresApproval
    case enabled
    case running
    case unavailable
    public var phrase: String {
        switch self {
        case .notInstalled: "Not installed"
        case .requiresApproval: "Waiting for approval"
        case .enabled: "Enabled"
        case .running: "Running"
        case .unavailable: "Unavailable"
        }
    }
}

public struct PureGymStatus: Codable, Sendable, Equatable {
    public var state: ServiceState
    public var accountEmail: String?
    public var memberName: String?
    public var homeGym: String?
    public var homeGymLocation: PassLocation?
    public var lastCheckedAt: Date?
    public var lastHTTPStatus: Int?
    public var lastLatencyMilliseconds: Int?
    public var authenticationValid: Bool
    public var tokenExpiresAt: Date?
    public init(state: ServiceState, accountEmail: String? = nil, memberName: String? = nil, homeGym: String? = nil, homeGymLocation: PassLocation? = nil, lastCheckedAt: Date? = nil, lastHTTPStatus: Int? = nil, lastLatencyMilliseconds: Int? = nil, authenticationValid: Bool = false, tokenExpiresAt: Date? = nil) {
        self.state = state; self.accountEmail = accountEmail; self.memberName = memberName
        self.homeGym = homeGym; self.homeGymLocation = homeGymLocation
        self.lastCheckedAt = lastCheckedAt; self.lastHTTPStatus = lastHTTPStatus
        self.lastLatencyMilliseconds = lastLatencyMilliseconds
        self.authenticationValid = authenticationValid; self.tokenExpiresAt = tokenExpiresAt
    }
}

public struct QRStatus: Codable, Sendable, Equatable {
    public var present: Bool
    public var retrievedAt: Date?
    public var expiresAt: Date?
    public var refreshAfter: Date?
    public var changedAt: Date?
    public var reportedExpiryPassed: Bool
    public init(present: Bool, retrievedAt: Date? = nil, expiresAt: Date? = nil, refreshAfter: Date? = nil, changedAt: Date? = nil, reportedExpiryPassed: Bool = false) {
        self.present = present; self.retrievedAt = retrievedAt; self.expiresAt = expiresAt
        self.refreshAfter = refreshAfter; self.changedAt = changedAt
        self.reportedExpiryPassed = reportedExpiryPassed
    }
}

public struct WalletStatus: Codable, Sendable, Equatable {
    public var state: ServiceState
    public var serialNumber: String?
    public var passTypeIdentifier: String?
    public var revision: Int?
    public var lastGeneratedAt: Date?
    public var lastPublishedAt: Date?
    public var registrationCount: Int
    public var appearance: PassAppearance
    public var location: PassLocation?
    public init(state: ServiceState, serialNumber: String? = nil, passTypeIdentifier: String? = nil, revision: Int? = nil, lastGeneratedAt: Date? = nil, lastPublishedAt: Date? = nil, registrationCount: Int = 0, appearance: PassAppearance = .default, location: PassLocation? = nil) {
        self.state = state; self.serialNumber = serialNumber
        self.passTypeIdentifier = passTypeIdentifier; self.revision = revision
        self.lastGeneratedAt = lastGeneratedAt; self.lastPublishedAt = lastPublishedAt
        self.registrationCount = registrationCount; self.appearance = appearance; self.location = location
    }
}

public struct SigningStatus: Codable, Sendable, Equatable {
    public var state: ServiceState
    public var passTypeIdentifier: String?
    public var teamIdentifier: String?
    public var subject: String?
    public var issuer: String?
    public var expiresAt: Date?
    public var privateKeyAvailable: Bool
    public var lastSelfTestAt: Date?
    public var selfTestPassed: Bool?
    public var detail: String?
    public init(state: ServiceState, passTypeIdentifier: String? = nil, teamIdentifier: String? = nil, subject: String? = nil, issuer: String? = nil, expiresAt: Date? = nil, privateKeyAvailable: Bool = false, lastSelfTestAt: Date? = nil, selfTestPassed: Bool? = nil, detail: String? = nil) {
        self.state = state; self.passTypeIdentifier = passTypeIdentifier
        self.teamIdentifier = teamIdentifier; self.subject = subject; self.issuer = issuer
        self.expiresAt = expiresAt; self.privateKeyAvailable = privateKeyAvailable
        self.lastSelfTestAt = lastSelfTestAt; self.selfTestPassed = selfTestPassed; self.detail = detail
    }

    public enum Kind: String, Codable, Sendable {
        case valid, expiringSoon, expired, missingPrivateKey, wrongPassType, signingFailed, notConfigured
    }
}

public struct APNsStatus: Codable, Sendable, Equatable {
    public var state: ServiceState
    public var lastAttemptAt: Date?
    public var lastAcceptedAt: Date?
    public var lastResultDescription: String?
    public var pendingCount: Int
    public init(state: ServiceState, lastAttemptAt: Date? = nil, lastAcceptedAt: Date? = nil, lastResultDescription: String? = nil, pendingCount: Int = 0) {
        self.state = state; self.lastAttemptAt = lastAttemptAt
        self.lastAcceptedAt = lastAcceptedAt; self.lastResultDescription = lastResultDescription
        self.pendingCount = pendingCount
    }
}

public struct ServerStatus: Codable, Sendable, Equatable {
    public var state: ServiceState
    public var host: String
    public var port: Int
    public var controlPort: Int
    public var requestCount: Int
    public var lastRequestAt: Date?
    public init(state: ServiceState, host: String = "127.0.0.1", port: Int = 8754, controlPort: Int = 8755, requestCount: Int = 0, lastRequestAt: Date? = nil) {
        self.state = state; self.host = host; self.port = port
        self.controlPort = controlPort; self.requestCount = requestCount; self.lastRequestAt = lastRequestAt
    }
}

public struct TunnelStatus: Codable, Sendable, Equatable {
    public var state: ServiceState
    public var provider: TunnelProviderKind
    public var publicHostname: String?
    public var lastConnectedAt: Date?
    public var lastError: String?
    public var binaryAvailable: Bool
    public var ephemeral: Bool
    public init(state: ServiceState, provider: TunnelProviderKind = .cloudflareNamed, publicHostname: String? = nil, lastConnectedAt: Date? = nil, lastError: String? = nil, binaryAvailable: Bool = false, ephemeral: Bool = false) {
        self.state = state; self.provider = provider
        self.publicHostname = publicHostname; self.lastConnectedAt = lastConnectedAt
        self.lastError = lastError; self.binaryAvailable = binaryAvailable; self.ephemeral = ephemeral
    }
}

public struct PublicEndpointStatus: Codable, Sendable, Equatable {
    public var state: ServiceState
    public var reachable: Bool
    public var latencyMilliseconds: Int?
    public var lastCheckedAt: Date?
    public var detail: String?
    public init(state: ServiceState, reachable: Bool = false, latencyMilliseconds: Int? = nil, lastCheckedAt: Date? = nil, detail: String? = nil) {
        self.state = state; self.reachable = reachable
        self.latencyMilliseconds = latencyMilliseconds; self.lastCheckedAt = lastCheckedAt; self.detail = detail
    }
}

public struct DatabaseStatus: Codable, Sendable, Equatable {
    public var state: ServiceState
    public var path: String
    public var sizeBytes: Int64
    public var migrationVersion: String
    public init(state: ServiceState, path: String, sizeBytes: Int64, migrationVersion: String) {
        self.state = state; self.path = path; self.sizeBytes = sizeBytes; self.migrationVersion = migrationVersion
    }
}
