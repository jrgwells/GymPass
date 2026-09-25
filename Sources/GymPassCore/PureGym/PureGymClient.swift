import Foundation
import GymPassShared

public actor PureGymClient: PureGymAPI {
    public struct Configuration: Sendable {
        public var authBaseURL: URL
        public var apiBaseURL: URL
        public var minimumRequestInterval: TimeInterval
        public var requestTimeout: TimeInterval

        public init(
            authBaseURL: URL = URL(string: "https://auth.puregym.com")!,
            apiBaseURL: URL = URL(string: "https://capi.puregym.com")!,
            minimumRequestInterval: TimeInterval = 30,
            requestTimeout: TimeInterval = 20
        ) {
            self.authBaseURL = authBaseURL
            self.apiBaseURL = apiBaseURL
            self.minimumRequestInterval = minimumRequestInterval
            self.requestTimeout = requestTimeout
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let rateLimiter: RateLimiter
    private var tokens: PureGymTokens?
    private var cachedGyms: [PureGymGym] = []

    /// Public client id used by the PureGym app. This is not a user secret.
    private static let basicClientID = "cm8uY2xpZW50Og=="

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.requestTimeout * 2
        sessionConfiguration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: sessionConfiguration)
        self.rateLimiter = RateLimiter(minimumInterval: configuration.minimumRequestInterval)
    }

    public func setTokens(_ tokens: PureGymTokens?) {
        self.tokens = tokens
    }

    public func currentTokens() -> PureGymTokens? {
        tokens
    }

    // MARK: - Authentication

    public func authenticate(email: String, pin: String) async throws -> PureGymTokens {
        let body = [
            "grant_type=password",
            "username=\(Self.formEncode(email))",
            "password=\(Self.formEncode(pin))",
            "scope=pgcapi%20offline_access",
        ].joined(separator: "&")

        let response = try await perform(
            base: configuration.authBaseURL,
            path: "/connect/token",
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Authorization": "Basic \(Self.basicClientID)",
            ],
            body: Data(body.utf8),
            allowRetry: false
        )
        guard (200..<300).contains(response.status) else {
            throw Self.error(for: response)
        }
        let newTokens = try decodeTokens(response.data)
        tokens = newTokens
        return newTokens
    }

    private func refresh(_ current: PureGymTokens) async throws -> PureGymTokens {
        guard let refreshToken = current.refreshToken else {
            throw GymPassError.authenticationRequired
        }
        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(Self.formEncode(refreshToken))",
            "scope=pgcapi%20offline_access",
        ].joined(separator: "&")
        let response = try await perform(
            base: configuration.authBaseURL,
            path: "/connect/token",
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Authorization": "Basic \(Self.basicClientID)",
            ],
            body: Data(body.utf8),
            allowRetry: false
        )
        guard (200..<300).contains(response.status) else {
            throw GymPassError.authenticationRequired
        }
        let newTokens = try decodeTokens(response.data)
        tokens = newTokens
        return newTokens
    }

    private func decodeTokens(_ data: Data) throws -> PureGymTokens {
        struct TokenResponse: Decodable {
            var access_token: String
            var refresh_token: String?
            var expires_in: Double?
        }
        do {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            let lifetime = decoded.expires_in ?? 3600
            return PureGymTokens(
                accessToken: decoded.access_token,
                refreshToken: decoded.refresh_token,
                expiresAt: Date().addingTimeInterval(lifetime)
            )
        } catch {
            throw GymPassError.decoding("The sign-in response could not be read.")
        }
    }

    // MARK: - Member data

    private func validAccessToken() async throws -> String {
        guard let current = tokens else { throw GymPassError.authenticationRequired }
        if current.expiresAt.timeIntervalSinceNow < 60, current.refreshToken != nil {
            let refreshed = try await refresh(current)
            return refreshed.accessToken
        }
        return current.accessToken
    }

    public func fetchQRCode() async throws -> PureGymQRCode {
        let response = try await authorizedGET(path: "/api/v2/member/qrcode")
        guard (200..<300).contains(response.status) else {
            throw Self.error(for: response)
        }
        do {
            return try JSONDecoder().decode(PureGymQRCode.self, from: response.data)
        } catch {
            throw GymPassError.decoding("The access code response could not be read.")
        }
    }

    public func fetchGyms() async throws -> [PureGymGym] {
        let response = try await authorizedGET(path: "/api/v1/gyms/")
        guard (200..<300).contains(response.status) else {
            throw Self.error(for: response)
        }
        do {
            let gyms = try JSONDecoder().decode([PureGymGym].self, from: response.data)
            cachedGyms = gyms
            return gyms
        } catch {
            throw GymPassError.decoding("The gym list could not be read.")
        }
    }

    public func fetchMember() async throws -> PureGymMember? {
        // The member endpoint shape is not guaranteed; treat absence as nil.
        for path in ["/api/v2/member", "/api/v1/member"] {
            guard let response = try? await authorizedGET(path: path),
                  (200..<300).contains(response.status) else { continue }
            if let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] {
                let name = (object["firstName"] as? String).flatMap { first in
                    (object["lastName"] as? String).map { "\(first) \($0)" } ?? first
                } ?? object["name"] as? String
                let homeGymID = (object["homeGymId"] as? Int) ?? (object["homeGymID"] as? Int)
                return PureGymMember(name: name, homeGymID: homeGymID, homeGymName: nil)
            }
        }
        return nil
    }

    public func connectivityTest() async throws -> PureGymConnectivityResult {
        let start = Date()
        let qr = try await fetchQRCode()
        let member = try? await fetchMember()
        var homeGym: PureGymGym?
        if let gyms = try? await fetchGyms(), let id = member?.homeGymID {
            homeGym = gyms.first { $0.id == id }
        }
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        let location: PassLocation? = {
            guard let gym = homeGym, let lat = gym.latitude, let lon = gym.longitude else { return nil }
            return PassLocation(label: gym.name, latitude: lat, longitude: lon, relevantText: gym.name)
        }()
        _ = qr
        return PureGymConnectivityResult(
            httpStatus: 200,
            latencyMilliseconds: latency,
            memberName: member?.name,
            homeGymName: homeGym?.name ?? member?.homeGymName,
            homeGymLocation: location
        )
    }

    // MARK: - HTTP

    private func authorizedGET(path: String) async throws -> HTTPResponse {
        var accessToken = try await validAccessToken()
        var response = try await perform(
            base: configuration.apiBaseURL,
            path: path,
            method: "GET",
            headers: ["Authorization": "Bearer \(accessToken)"],
            body: nil,
            allowRetry: true
        )
        if response.status == 401, let current = tokens, current.refreshToken != nil {
            let refreshed = try await refresh(current)
            accessToken = refreshed.accessToken
            response = try await perform(
                base: configuration.apiBaseURL,
                path: path,
                method: "GET",
                headers: ["Authorization": "Bearer \(accessToken)"],
                body: nil,
                allowRetry: true
            )
        }
        return response
    }

    private func perform(
        base: URL,
        path: String,
        method: String,
        headers: [String: String],
        body: Data?,
        allowRetry: Bool
    ) async throws -> HTTPResponse {
        await rateLimiter.acquire()
        guard let url = URL(string: path, relativeTo: base) else {
            throw GymPassError.transport("Invalid request URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GymPassError.transport("Unexpected response type")
            }
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            var headerMap: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headerMap[key.lowercased()] = value
                }
            }
            if let retryAfter = headerMap["retry-after"].flatMap(Int.init) {
                await rateLimiter.noteRetryAfter(seconds: retryAfter)
            }
            Log.puregym.debug("\(method, privacy: .public) \(path, privacy: .public) -> \(http.statusCode, privacy: .public) in \(latency, privacy: .public)ms")
            return HTTPResponse(status: http.statusCode, data: data, headers: headerMap, latencyMilliseconds: latency)
        } catch let error as GymPassError {
            throw error
        } catch {
            throw GymPassError.transport(Redactor.redact(String(describing: error)))
        }
    }

    private static func error(for response: HTTPResponse) -> GymPassError {
        if response.status == 401 || response.status == 403 {
            return .authenticationRequired
        }
        if response.status == 429 {
            let retry = response.headers["retry-after"].flatMap(Int.init)
            return .rateLimited(retryAfterSeconds: retry)
        }
        if response.status >= 500 {
            return .server(status: response.status, message: "PureGym is temporarily unavailable.")
        }
        return .server(status: response.status, message: nil)
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
