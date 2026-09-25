import Foundation
import GymPassShared
import GymPassCore

/// Non-secret agent configuration, persisted as JSON in the database. Secrets
/// (credentials, tokens, tunnel credentials) live in the Keychain.
public struct AgentConfiguration: Codable, Sendable, Equatable {
    public var appearance: PassAppearance
    public var location: PassLocation?
    public var policy: RefreshPolicy
    public var preferences: AppPreferences
    public var tunnel: TunnelConfiguration
    public var accountEmail: String?
    public var memberName: String?
    public var homeGymName: String?
    public var apnsEnvironment: APNsEnvironment

    public init(
        appearance: PassAppearance = .default,
        location: PassLocation? = nil,
        policy: RefreshPolicy = .default,
        preferences: AppPreferences = .default,
        tunnel: TunnelConfiguration = TunnelConfiguration(),
        accountEmail: String? = nil,
        memberName: String? = nil,
        homeGymName: String? = nil,
        apnsEnvironment: APNsEnvironment = .production
    ) {
        self.appearance = appearance
        self.location = location
        self.policy = policy
        self.preferences = preferences
        self.tunnel = tunnel
        self.accountEmail = accountEmail
        self.memberName = memberName
        self.homeGymName = homeGymName
        self.apnsEnvironment = apnsEnvironment
    }

    public static let `default` = AgentConfiguration()
    public static let configKey = "agent.configuration"
}
