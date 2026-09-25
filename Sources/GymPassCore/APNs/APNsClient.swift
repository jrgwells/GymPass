import Foundation
import Security
import GymPassShared

public enum APNsEnvironment: String, Sendable, Codable, CaseIterable {
    case production
    case sandbox

    public var host: String {
        switch self {
        case .production: "api.push.apple.com"
        case .sandbox: "api.sandbox.push.apple.com"
        }
    }
}

public enum APNsResult: Sendable, Equatable {
    case accepted(apnsID: String?)
    case invalidToken(reason: String?)
    case topicMismatch(reason: String?)
    case transient(status: Int, reason: String?)
    case rejected(status: Int, reason: String?)
}

/// Header policy for Wallet pass-update pushes, isolated in one place so it can
/// be adjusted against a real device without touching the client.
///
/// Wallet pass notifications use certificate authentication, the pass type
/// identifier as the topic and an empty JSON dictionary body. The exact
/// `apns-push-type`/priority combination must be confirmed on a real pass.
public struct WalletAPNsPolicy: Sendable {
    public var topic: String
    public var pushType: String
    public var priority: Int
    public var body: Data

    public init(topic: String, pushType: String = "alert", priority: Int = 5, body: Data = Data("{}".utf8)) {
        self.topic = topic
        self.pushType = pushType
        self.priority = priority
        self.body = body
    }
}

public protocol APNsSending: Sendable {
    func send(pushToken: Data, policy: WalletAPNsPolicy) async -> APNsResult
}

/// Sends Wallet update notifications over HTTP/2 using the pass signing
/// certificate for client authentication.
public actor APNsClient: APNsSending {
    private let identityProvider: @Sendable () async -> IdentityBox?
    private let environment: APNsEnvironment
    private let timeout: TimeInterval

    public init(
        environment: APNsEnvironment = .production,
        timeout: TimeInterval = 20,
        identityProvider: @escaping @Sendable () async -> IdentityBox?
    ) {
        self.environment = environment
        self.timeout = timeout
        self.identityProvider = identityProvider
    }

    public func send(pushToken: Data, policy: WalletAPNsPolicy) async -> APNsResult {
        guard let box = await identityProvider() else {
            return .rejected(status: 0, reason: "No signing identity is configured.")
        }
        let tokenHex = pushToken.map { String(format: "%02x", $0) }.joined()
        guard let url = URL(string: "https://\(environment.host)/3/device/\(tokenHex)") else {
            return .rejected(status: 0, reason: "Invalid push token.")
        }

        let delegate = APNsSessionDelegate(identity: box.identity)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = policy.body
        request.setValue(policy.topic, forHTTPHeaderField: "apns-topic")
        request.setValue(policy.pushType, forHTTPHeaderField: "apns-push-type")
        request.setValue(String(policy.priority), forHTTPHeaderField: "apns-priority")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        do {
            let (data, response) = try await session.data(for: request)
            session.finishTasksAndInvalidate()
            guard let http = response as? HTTPURLResponse else {
                return .transient(status: 0, reason: "Unexpected response")
            }
            let apnsID = http.value(forHTTPHeaderField: "apns-id")
            if http.statusCode == 200 {
                Log.apns.info("Apple accepted a Wallet update notification")
                return .accepted(apnsID: apnsID)
            }
            let reason = Self.reason(from: data)
            Log.apns.error("APNs rejected a notification: \(http.statusCode, privacy: .public) \(reason ?? "unknown", privacy: .public)")
            switch http.statusCode {
            case 400 where reason == "BadDeviceToken" || reason == "DeviceTokenNotForTopic":
                return .invalidToken(reason: reason)
            case 403:
                return .topicMismatch(reason: reason)
            case 404 where reason == "BadPath":
                return .invalidToken(reason: reason)
            case 410:
                return .invalidToken(reason: reason ?? "Unregistered")
            case 429, 500, 503:
                return .transient(status: http.statusCode, reason: reason)
            default:
                return .rejected(status: http.statusCode, reason: reason)
            }
        } catch {
            session.invalidateAndCancel()
            Log.apns.error("APNs request failed: \(Redactor.redact(String(describing: error)), privacy: .public)")
            return .transient(status: 0, reason: "Network error")
        }
    }

    private static func reason(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["reason"] as? String
    }
}

final class APNsSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let identity: SecIdentity

    init(identity: SecIdentity) {
        self.identity = identity
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            let credential = URLCredential(identity: identity, certificates: nil, persistence: .none)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
