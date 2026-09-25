import Foundation
import GymPassShared

public protocol PureGymAPI: Sendable {
    func authenticate(email: String, pin: String) async throws -> PureGymTokens
    func setTokens(_ tokens: PureGymTokens?) async
    func currentTokens() async -> PureGymTokens?
    func fetchQRCode() async throws -> PureGymQRCode
    func fetchGyms() async throws -> [PureGymGym]
    func fetchMember() async throws -> PureGymMember?
    func connectivityTest() async throws -> PureGymConnectivityResult
}

struct HTTPResponse: Sendable {
    var status: Int
    var data: Data
    var headers: [String: String]
    var latencyMilliseconds: Int
}
