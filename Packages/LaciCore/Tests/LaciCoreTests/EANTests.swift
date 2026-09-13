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

    @Test("Every symbology the camera can emit maps back from its AVFoundation type string", arguments: [
        ("org.gs1.EAN-13", Symbology.ean13), ("org.gs1.EAN-8", .ean8), ("org.gs1.UPC-E", .upce),
        ("org.iso.Code128", .code128), ("org.iso.Code39", .code39), ("org.gs1.ITF14", .itf14),
        ("org.iso.QRCode", .qrCode),
    ])
    func symbologyFromType(raw: String, symbology: Symbology) {
        #expect(Symbology(rawValue: raw) == symbology)
    }
}
