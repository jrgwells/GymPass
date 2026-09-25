import Foundation

public enum GymPassError: Error, Sendable, Equatable {
    case notConfigured(String)
    case authenticationRequired
    case authenticationFailed
    case transport(String)
    case server(status: Int, message: String?)
    case rateLimited(retryAfterSeconds: Int?)
    case decoding(String)
    case signingUnavailable(String)
    case signingFailed(String)
    case verificationFailed(String)
    case persistence(String)
    case keychain(OSStatus)
    case crypto(String)
    case invalidRequest(String)
    case unauthorized(String)
    case notFound(String)
    case conflict(String)
    case internalError(String)

    public var code: String {
        switch self {
        case .notConfigured: "not_configured"
        case .authenticationRequired: "authentication_required"
        case .authenticationFailed: "authentication_failed"
        case .transport: "transport_error"
        case .server: "server_error"
        case .rateLimited: "rate_limited"
        case .decoding: "decoding_error"
        case .signingUnavailable: "signing_unavailable"
        case .signingFailed: "signing_failed"
        case .verificationFailed: "verification_failed"
        case .persistence: "persistence_error"
        case .keychain: "keychain_error"
        case .crypto: "crypto_error"
        case .invalidRequest: "invalid_request"
        case .unauthorized: "unauthorized"
        case .notFound: "not_found"
        case .conflict: "conflict"
        case .internalError: "internal_error"
        }
    }

    public var userMessage: String {
        switch self {
        case .notConfigured(let what): "\(what) is not configured yet."
        case .authenticationRequired: "PureGym needs you to sign in again."
        case .authenticationFailed: "PureGym could not sign you in."
        case .transport: "GymPass could not reach the network."
        case .server(_, let message): message ?? "The service returned an error."
        case .rateLimited: "The service asked GymPass to slow down."
        case .decoding: "The service returned something GymPass did not understand."
        case .signingUnavailable: "A signing certificate is required."
        case .signingFailed: "GymPass could not sign the pass."
        case .verificationFailed: "The generated pass failed verification."
        case .persistence: "GymPass could not read or write its database."
        case .keychain: "GymPass could not access a stored secret."
        case .crypto: "GymPass could not protect stored data."
        case .invalidRequest: "That request was not valid."
        case .unauthorized: "That request was not authorised."
        case .notFound: "That item was not found."
        case .conflict: "That action conflicts with existing data."
        case .internalError: "GymPass hit an unexpected problem."
        }
    }

    public var payload: AgentErrorPayload {
        let detail: String?
        switch self {
        case .transport(let text), .decoding(let text), .signingUnavailable(let text),
             .signingFailed(let text), .verificationFailed(let text), .persistence(let text),
             .crypto(let text), .invalidRequest(let text), .unauthorized(let text),
             .notFound(let text), .conflict(let text), .internalError(let text):
            detail = text
        case .server(let status, let message):
            detail = "HTTP \(status)\(message.map { ": \($0)" } ?? "")"
        case .rateLimited(let retry):
            detail = retry.map { "Retry after \($0)s" }
        case .keychain(let status):
            detail = "OSStatus \(status)"
        default:
            detail = nil
        }
        return AgentErrorPayload(code: code, message: userMessage, detail: detail)
    }
}
