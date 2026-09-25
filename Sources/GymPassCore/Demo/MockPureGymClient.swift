import Foundation
import GymPassShared

/// Deterministic PureGym stand-in for demo mode and tests.
public actor MockPureGymClient: PureGymAPI {
    public enum FailureMode: String, Sendable {
        case none
        case serverError
        case unauthorized
        case offline
    }

    private var tokens: PureGymTokens?
    private var generation = 0
    private let changeEverySeconds: TimeInterval
    private let validitySeconds: TimeInterval
    private var failureMode: FailureMode = .none

    public init(changeEverySeconds: TimeInterval = 60, validitySeconds: TimeInterval = 7 * 24 * 3600) {
        self.changeEverySeconds = changeEverySeconds
        self.validitySeconds = validitySeconds
    }

    public func setFailureMode(_ mode: FailureMode) {
        failureMode = mode
    }

    public func setTokens(_ tokens: PureGymTokens?) {
        self.tokens = tokens
    }

    public func currentTokens() -> PureGymTokens? {
        tokens
    }

    public func authenticate(email: String, pin: String) async throws -> PureGymTokens {
        switch failureMode {
        case .offline: throw GymPassError.transport("Demo: network unavailable")
        case .serverError: throw GymPassError.server(status: 500, message: "Demo failure")
        case .unauthorized: throw GymPassError.authenticationFailed
        case .none: break
        }
        let result = PureGymTokens(accessToken: "demo-access-\(generation)", refreshToken: "demo-refresh", expiresAt: Date().addingTimeInterval(3600))
        tokens = result
        return result
    }

    public func fetchQRCode() async throws -> PureGymQRCode {
        switch failureMode {
        case .offline: throw GymPassError.transport("Demo: network unavailable")
        case .serverError: throw GymPassError.server(status: 500, message: "Demo failure")
        case .unauthorized: throw GymPassError.authenticationRequired
        case .none: break
        }
        generation += 1
        let now = Date()
        let bucket = Int(now.timeIntervalSince1970 / changeEverySeconds)
        let code = "exerp:checkin:demo-\(bucket)-\(generation)"
        return PureGymQRCode(
            code: code,
            refreshAt: now.addingTimeInterval(changeEverySeconds),
            expiresAt: now.addingTimeInterval(validitySeconds),
            refreshIn: changeEverySeconds,
            expiresIn: validitySeconds
        )
    }

    public func fetchGyms() async throws -> [PureGymGym] {
        [
            PureGymGym(id: 318, name: "PureGym Bagshot", latitude: 51.3432, longitude: -0.6987),
            PureGymGym(id: 234, name: "PureGym Camberley", latitude: 51.3354, longitude: -0.7428),
        ]
    }

    public func fetchMember() async throws -> PureGymMember? {
        PureGymMember(name: "Jack", homeGymID: 318, homeGymName: "PureGym Bagshot")
    }

    public func connectivityTest() async throws -> PureGymConnectivityResult {
        let gyms = try await fetchGyms()
        let member = try await fetchMember()
        let gym = gyms.first { $0.id == member?.homeGymID }
        let location = gym.flatMap { g -> PassLocation? in
            guard let lat = g.latitude, let lon = g.longitude else { return nil }
            return PassLocation(label: g.name, latitude: lat, longitude: lon, relevantText: g.name)
        }
        return PureGymConnectivityResult(
            httpStatus: 200,
            latencyMilliseconds: 42,
            memberName: member?.name,
            homeGymName: gym?.name,
            homeGymLocation: location
        )
    }
}
