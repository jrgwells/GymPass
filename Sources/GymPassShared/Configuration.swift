import Foundation

public struct PassAppearance: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var gymLabel: String
    public var memberName: String?
    public var showMemberName: Bool
    public var foregroundHex: String
    public var backgroundHex: String
    public var labelHex: String
    public var logoFileName: String?

    public init(
        title: String = "GymPass",
        gymLabel: String = "PureGym",
        memberName: String? = nil,
        showMemberName: Bool = true,
        foregroundHex: String = "#FFFFFF",
        backgroundHex: String = "#6A35D4",
        labelHex: String = "#E7DDFF",
        logoFileName: String? = nil
    ) {
        self.title = title
        self.gymLabel = gymLabel
        self.memberName = memberName
        self.showMemberName = showMemberName
        self.foregroundHex = foregroundHex
        self.backgroundHex = backgroundHex
        self.labelHex = labelHex
        self.logoFileName = logoFileName
    }

    public static let `default` = PassAppearance()
}

public struct PassLocation: Codable, Sendable, Equatable, Hashable {
    public var label: String
    public var latitude: Double
    public var longitude: Double
    public var relevantText: String?

    public init(label: String, latitude: Double, longitude: Double, relevantText: String? = nil) {
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
        self.relevantText = relevantText
    }
}

public enum TunnelProviderKind: String, Codable, Sendable, CaseIterable {
    case cloudflareNamed
    case cloudflareQuick

    public var displayName: String {
        switch self {
        case .cloudflareNamed: "Cloudflare Tunnel"
        case .cloudflareQuick: "Cloudflare Quick Tunnel (testing)"
        }
    }
}

public struct TunnelConfiguration: Codable, Sendable, Equatable {
    public var provider: TunnelProviderKind
    public var publicHostname: String?
    public var tunnelName: String?
    /// True when credentials have been stored in the Keychain.
    public var hasStoredCredentials: Bool
    public var localWalletPort: Int

    public init(
        provider: TunnelProviderKind = .cloudflareNamed,
        publicHostname: String? = nil,
        tunnelName: String? = nil,
        hasStoredCredentials: Bool = false,
        localWalletPort: Int = 8754
    ) {
        self.provider = provider
        self.publicHostname = publicHostname
        self.tunnelName = tunnelName
        self.hasStoredCredentials = hasStoredCredentials
        self.localWalletPort = localWalletPort
    }
}

public enum RefreshMode: String, Codable, Sendable, CaseIterable {
    case conservative
    case balanced
    case aggressive

    public var displayName: String {
        switch self {
        case .conservative: "Conservative"
        case .balanced: "Balanced"
        case .aggressive: "Aggressive"
        }
    }

    public var explanation: String {
        switch self {
        case .conservative: "Refreshes only when the access code is close to expiry."
        case .balanced: "Refreshes at a steady, server-friendly rate."
        case .aggressive: "Refreshes frequently for a bounded period."
        }
    }
}

public struct RefreshPolicy: Codable, Sendable, Equatable {
    public var mode: RefreshMode
    /// Minimum seconds between QR retrievals regardless of hints.
    public var floorIntervalSeconds: Int
    /// Safety margin before reported expiry at which to refresh.
    public var expirySafetyMarginSeconds: Int
    /// Maximum duration of an aggressive burst.
    public var aggressiveMaxDurationSeconds: Int
    /// Maximum requests in an aggressive burst.
    public var aggressiveBudget: Int

    public init(
        mode: RefreshMode = .balanced,
        floorIntervalSeconds: Int = 300,
        expirySafetyMarginSeconds: Int = 3600,
        aggressiveMaxDurationSeconds: Int = 1800,
        aggressiveBudget: Int = 120
    ) {
        self.mode = mode
        self.floorIntervalSeconds = floorIntervalSeconds
        self.expirySafetyMarginSeconds = expirySafetyMarginSeconds
        self.aggressiveMaxDurationSeconds = aggressiveMaxDurationSeconds
        self.aggressiveBudget = aggressiveBudget
    }

    public static let `default` = RefreshPolicy()
}

public struct AppPreferences: Codable, Sendable, Equatable {
    public var launchAgentAtLogin: Bool
    public var showMenuBarItem: Bool
    public var openAtLogin: Bool
    public var notifyImportantProblems: Bool
    public var notifyCertificateExpiry: Bool
    public var keepMacAwake: Bool
    public var developerLogging: Bool

    public init(
        launchAgentAtLogin: Bool = true,
        showMenuBarItem: Bool = true,
        openAtLogin: Bool = false,
        notifyImportantProblems: Bool = true,
        notifyCertificateExpiry: Bool = true,
        keepMacAwake: Bool = false,
        developerLogging: Bool = false
    ) {
        self.launchAgentAtLogin = launchAgentAtLogin
        self.showMenuBarItem = showMenuBarItem
        self.openAtLogin = openAtLogin
        self.notifyImportantProblems = notifyImportantProblems
        self.notifyCertificateExpiry = notifyCertificateExpiry
        self.keepMacAwake = keepMacAwake
        self.developerLogging = developerLogging
    }

    public static let `default` = AppPreferences()
}

public struct PassFacts: Codable, Sendable, Equatable {
    public var passTypeIdentifier: String?
    public var teamIdentifier: String?
    public var serialNumber: String?
    public init(passTypeIdentifier: String? = nil, teamIdentifier: String? = nil, serialNumber: String? = nil) {
        self.passTypeIdentifier = passTypeIdentifier
        self.teamIdentifier = teamIdentifier
        self.serialNumber = serialNumber
    }
}
