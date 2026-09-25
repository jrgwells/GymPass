import Foundation
import GymPassShared
import CryptoKit

/// Authenticated encryption for at-rest blobs. Uses AES-GCM via CryptoKit.
/// The key lives in the Keychain and is never persisted alongside the data.
public struct CryptoBox: Sendable {
    private let key: SymmetricKey

    public init(key: Data) {
        self.key = SymmetricKey(data: key)
    }

    public static func randomKey() -> Data {
        SecureRandom.bytes(32)
    }

    public func seal(_ plaintext: Data) throws -> Data {
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else {
                throw GymPassError.crypto("AES-GCM produced no combined representation")
            }
            return combined
        } catch let error as GymPassError {
            throw error
        } catch {
            throw GymPassError.crypto("Encryption failed")
        }
    }

    public func seal(_ string: String) throws -> Data {
        guard let data = string.data(using: .utf8) else {
            throw GymPassError.crypto("Could not encode string")
        }
        return try seal(data)
    }

    public func open(_ ciphertext: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw GymPassError.crypto("Decryption failed")
        }
    }

    public func openString(_ ciphertext: Data) throws -> String {
        let data = try open(ciphertext)
        guard let string = String(data: data, encoding: .utf8) else {
            throw GymPassError.crypto("Decrypted data was not UTF-8")
        }
        return string
    }
}
