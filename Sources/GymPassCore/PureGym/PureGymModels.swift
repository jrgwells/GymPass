import Foundation
import GymPassShared

public struct PureGymTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public struct PureGymQRCode: Codable, Sendable, Equatable {
    public var code: String
    public var refreshAt: Date?
    public var expiresAt: Date?
    public var refreshIn: TimeInterval?
    public var expiresIn: TimeInterval?

    public init(code: String, refreshAt: Date?, expiresAt: Date?, refreshIn: TimeInterval?, expiresIn: TimeInterval?) {
        self.code = code
        self.refreshAt = refreshAt
        self.expiresAt = expiresAt
        self.refreshIn = refreshIn
        self.expiresIn = expiresIn
    }

    enum CodingKeys: String, CodingKey {
        case code = "QrCode"
        case refreshAt = "RefreshAt"
        case expiresAt = "ExpiresAt"
        case refreshIn = "RefreshIn"
        case expiresIn = "ExpiresIn"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        refreshAt = GymPassDate.parse(try container.decodeIfPresent(String.self, forKey: .refreshAt) ?? "")
        expiresAt = GymPassDate.parse(try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? "")
        if let refreshInString = try container.decodeIfPresent(String.self, forKey: .refreshIn) {
            refreshIn = GymPassDate.parseDuration(refreshInString)
        }
        if let expiresInString = try container.decodeIfPresent(String.self, forKey: .expiresIn) {
            expiresIn = GymPassDate.parseDuration(expiresInString)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(refreshAt.map(GymPassDate.iso8601), forKey: .refreshAt)
        try container.encodeIfPresent(expiresAt.map(GymPassDate.iso8601), forKey: .expiresAt)
    }
}

public struct PureGymGym: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var latitude: Double?
    public var longitude: Double?

    public init(id: Int, name: String, latitude: Double?, longitude: Double?) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        name = (try? container.decode(String.self, forKey: .name)) ?? "PureGym"
        if let latString = try? container.decode(String.self, forKey: .latitude) {
            latitude = Double(latString)
        } else {
            latitude = try? container.decode(Double.self, forKey: .latitude)
        }
        if let lonString = try? container.decode(String.self, forKey: .longitude) {
            longitude = Double(lonString)
        } else {
            longitude = try? container.decode(Double.self, forKey: .longitude)
        }
    }
}

public struct PureGymMember: Codable, Sendable, Equatable {
    public var name: String?
    public var homeGymID: Int?
    public var homeGymName: String?

    public init(name: String?, homeGymID: Int?, homeGymName: String?) {
        self.name = name
        self.homeGymID = homeGymID
        self.homeGymName = homeGymName
    }
}

public struct PureGymConnectivityResult: Sendable, Equatable {
    public var httpStatus: Int
    public var latencyMilliseconds: Int
    public var memberName: String?
    public var homeGymName: String?
    public var homeGymLocation: PassLocation?

    public init(httpStatus: Int, latencyMilliseconds: Int, memberName: String?, homeGymName: String?, homeGymLocation: PassLocation?) {
        self.httpStatus = httpStatus
        self.latencyMilliseconds = latencyMilliseconds
        self.memberName = memberName
        self.homeGymName = homeGymName
        self.homeGymLocation = homeGymLocation
    }
}
