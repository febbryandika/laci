import CryptoKit
import Foundation
@testable import Laci
import Testing

@Suite("PIN record")
struct PINRecordTests {
    @Test("The digest is the SHA-256 of salt + PIN, and the PIN itself is not stored")
    func digestIsSaltedSHA256() throws {
        let salt = Data([1, 2, 3, 4])
        let record = PINRecord(pin: "123456", salt: salt)
        #expect(record.digest == Data(SHA256.hash(data: salt + Data("123456".utf8))))
        let encoded = try JSONEncoder().encode(record)
        #expect(String(bytes: encoded, encoding: .utf8)?.contains("123456") == false)
    }

    @Test("Only the same PIN matches")
    func matches() {
        let record = PINRecord(pin: "123456")
        #expect(record.matches("123456"))
        #expect(!record.matches("123457"))
        #expect(!record.matches(""))
    }

    @Test("Two records of one PIN differ, so the store never shows that two PINs are equal")
    func saltIsRandom() {
        let first = PINRecord(pin: "123456"), second = PINRecord(pin: "123456")
        #expect(first.salt != second.salt)
        #expect(first.digest != second.digest)
        #expect(first.salt.count == 16)
    }

    @Test("Exactly six ASCII digits", arguments: [
        ("123456", true), ("000000", true), ("12345", false), ("1234567", false), ("", false),
        ("12a456", false), ("١٢٣٤٥٦", false), ("12 456", false),
    ])
    func format(pin: String, valid: Bool) {
        #expect(PINRecord.isValid(pin) == valid)
    }
}
