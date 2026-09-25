import Foundation
import CryptoKit

public enum PassManifest {
    /// SHA-1 hashes as required by the Wallet manifest format.
    public static func hashes(files: [String: Data]) -> [String: String] {
        var result: [String: String] = [:]
        for (name, data) in files {
            let digest = Insecure.SHA1.hash(data: data)
            result[name] = digest.map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    public static func data(files: [String: Data]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(hashes(files: files))
    }

    public static func decode(_ data: Data) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: data)
    }
}

public enum ArchiveContentHash {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }
}
