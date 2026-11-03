import CryptoKit
import Foundation

/// A PIN as it is kept (SPEC §15): a random salt and the SHA-256 of salt + PIN, never the PIN.
/// A million possible PINs make this hash quick to brute-force once it is off the device, so what
/// actually protects it is the Keychain item staying on this device (`KeychainPINStore`).
nonisolated struct PINRecord: Codable, Hashable, Sendable {
    static let length = 6
    private static let saltByteCount = 16

    let salt: Data
    let digest: Data

    init(pin: String) {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0 ..< Self.saltByteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        self.init(pin: pin, salt: Data(bytes))
    }

    init(pin: String, salt: Data) {
        self.salt = salt
        digest = Data(Self.hash(pin: pin, salt: salt))
    }

    /// `Digest`'s comparison with a `DataProtocol` runs in constant time.
    func matches(_ pin: String) -> Bool {
        Self.hash(pin: pin, salt: salt) == digest
    }

    /// Exactly six ASCII digits. `Character.isNumber` would also accept Arabic-Indic digits.
    static func isValid(_ pin: String) -> Bool {
        pin.utf8.count == length && pin.utf8.allSatisfy { (0x30 ... 0x39).contains($0) }
    }

    private static func hash(pin: String, salt: Data) -> SHA256.Digest {
        SHA256.hash(data: salt + Data(pin.utf8))
    }
}
