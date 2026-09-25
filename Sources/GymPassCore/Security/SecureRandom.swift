import Foundation
import GymPassShared
import Security

public enum SecureRandom {
    public static func bytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        precondition(result == errSecSuccess, "SecRandomCopyBytes failed")
        return data
    }

    /// URL-safe random token, default 32 bytes (256 bits).
    public static func token(byteCount: Int = 32) -> String {
        bytes(byteCount).base64URLEncodedString()
    }

    public static func hex(_ count: Int) -> String {
        bytes(count).map { String(format: "%02x", $0) }.joined()
    }
}

public extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var value = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value.append("=") }
        self.init(base64Encoded: value)
    }
}
