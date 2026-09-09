import LaciCore
import Testing

@Suite("EAN check digits")
struct EANTests {
    @Test("Valid payloads report their symbology", arguments: [
        ("5901234123457", Symbology.ean13), ("8992761111083", .ean13), ("96385074", .ean8),
    ])
    func valid(payload: String, symbology: Symbology) {
        #expect(EAN.validate(payload) == .valid(symbology))
    }

    @Test("A single wrong digit is a bad checksum, not an unknown product", arguments: [
        "5901234123458", "8992761111084", "96385075", "5901234123447",
    ])
    func badChecksum(payload: String) {
        #expect(EAN.validate(payload) == .badChecksum)
    }

    @Test("Anything that is not 8 or 13 ASCII digits is not an EAN", arguments: [
        "ABC123", "590123412345", "", "590123412345７", "ABC-99", "59012341234567",
    ])
    func notEAN(payload: String) {
        #expect(EAN.validate(payload) == .notEAN)
    }
}
